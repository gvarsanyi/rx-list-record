
ksc.factory 'ksc.ListMask', [
  '$rootScope', 'ksc.ArrayTracker', 'ksc.EventEmitter', 'ksc.List',
  'ksc.ListMapper', 'ksc.ListSorter', 'ksc.Record', 'ksc.error', 'ksc.util',
  ($rootScope, ArrayTracker, EventEmitter, List,
   ListMapper, ListSorter, Record, error, util) ->

    SCOPE_UNSUBSCRIBER = '_scopeUnsubscriber'

    argument_type_error = error.ArgumentType

    define_get_set = util.defineGetSet
    define_value   = util.defineValue
    is_object      = util.isObject


    ###
    Masked list that picks up changes from parent {List} instance(s)
    Features:
    - may be a composite of multiple named parents/sources to combine different
    kinds of records in the list. That also addes namespaces to .idMap and
    .pseudoMap containers like: .idMap.sourcelistname
    - May filter records (by provided function)
    - May have its own sorter, see: {ListSorter}

    Adding to or removing from a ListMask is not allowed, all of those
    operations should happen on the parent list and autmatically boild down.

    This list also emits appropriate events on changes, just like {List} does
    so {ListMask}s can also be marked as source/parent for other {ListMask}s.

    @example
            list = new List
            list.push {id: 1, x: 'aaa'}, {id: 2, x: 'baa'}, {id: 3, x: 'ccc'}

            filter_fn = (record) -> # filter to .x properties that have char 'a'
              String(record.x).indexOf('a') > -1

            sublist = new ListMask list, filter_fn
            console.log sublist # [{id: 1, x: 'aaa'}, {id: 2, x: 'baa'}]

            list.idMap[1].x = 'xxx' # should remove item form sublist as it does
                                    # not meet filter_fn requirement any more

            console.log sublist # [{id: 2, x: 'baa'}]

    @note Do not forget to manage the lifecycle of lists to prevent memory leaks
    @example
            # You may tie the lifecycle easily to a controller $scope by
            # just passing it to the constructor as last argument (arg #3 or #4)
            sublist = new ListMask list, filter_fn, $scope

            # you can destroy it at any time though:
            sublist.destroy()

    May also get two or more {List}s to form composite lists.
    In this case, sources must be named so that .idMap.name and .pseudoMap.name
    references can be used for mapping.

    @example
            list1 = new List
            list1.push {id: 1, x: 'aaa'}, {id: 2, x: 'baa'}, {id: 3, x: 'ccc'}

            list2 = new List
            list2.push {id2: 1, x: 'a'}, {id2: 22, x: 'b'}

            filter_fn = (record) -> # filter to .x properties that have char 'a'
              String(record.x).indexOf('a') > -1

            sublist = new ListMask {one: list1, two: list2}, filter_fn
            console.log sublist # [{id: 1, x: 'aaa'}, {id: 2, x: 'baa'},
                                #  {id2: 1, x: 'a'}]

            list.idMap.one[1].x = 'xxx' # removes item form sublist as it doesnt
                                        # meet filter_fn requirement any more

            console.log sublist # [{id: 2, x: 'baa'}, {id2: 1, x: 'a'}]

    A splitter function may also be added to trigger split records appearing in
    the list mask (but not on .idMap or .pseudoMap where the original record
    would appear only). Split records are masks of records that have the same
    attributes as the original record, except:
    - The override attributes from the filter_fn will be added as read-only
    - The original attributes appear as getter/setter pass-thorugh to the
    original record
    - A reference added to the original record: ._original

    @example
            list = new List
            list.push {id: 1, start: 30, end: 50}, {id: 2, start: 7, end: 8},
                      {id: 3, start: 20, end: 41}

            splitter = (record) ->
              step = 10
              if record.end - record.start > step # break it to 10-long units
                fakes = for i in [record.start ... record.end] by step
                  {start: i, end: Math.min record.end, i + step}
                return fakes
              false

            sublist = new ListMask list, {splitter}
            console.log sublist
            # [{id: 1, start: 30, end: 40}, {id: 1, start: 40, end: 50},
            #  {id: 2, start: 7, end: 8}, {id: 3, start: 20, end: 30},
            #  {id: 3, start: 30, end: 40}, {id: 3, start: 40, end: 41}]

    @author Greg Varsanyi
    ###
    class ListMask

      ###
      @property [ListMapper] helper object that handles references to records
        by their unique IDs (._id) or pseudo IDs (._pseudo)
      ###
      _mapper: undefined #DOC-ONLY#

      # @property [Object] map of replaced methods. This actually contains
      #   replacment methods from ArrayTracker, see actual original methods at
      #   {ArrayTracker#origFn}
      _origFn: undefined #DOC-ONLY#

      # @property [ArrayTracker] reference to getter/setter management object
      _tracker: undefined #DOC-ONLY#

      # @property [EventEmitter] reference to related event-emitter instance
      events: undefined #DOC-ONLY#

      # @property [object] hash map of records (keys being record ._id values)
      idMap: undefined #DOC-ONLY#

      # @property [object] filtered list related options
      options: undefined #DOC-ONLY#

      # @property [object] hash map of records without ._id keys
      pseudoMap: undefined #DOC-ONLY#

      # @property [object] reference to parent list
      source: undefined #DOC-ONLY#


      ###
      Creates a vanilla Array instance (e.g. []), disables methods like
      pop/shift/push/unshift since thes are supposed to be used on the source
      (aka parent) list only

      @note If a single {List} or {ListMask} source/parent is provided as first
        argument, .idMap and .pseudoMap references will work just like in {List}
        If object with key-value pairs provided (values being sources/parents),
        records get mapped like .idMap.keyname[id] and
        .pseudoMap.keyname[pseudo_id]

      @overload constructor(source, options, scope)
        @param [List/Object] source reference(s) to parent {List}(s)
        @param [Object] options (optional) configuration
        @param [ControllerScope] scope (optional) auto-unsubscribe on $scope
          '$destroy' event
      @overload constructor(source, filter, options, scope)
        @param [List/Object] source reference(s) to parent {List}(s)
        @param [function] filter function with signiture `(record) ->` and
          boolean return value indicating if record should appear in the list
        @param [Object] options (optional) configuration
        @param [ControllerScope] scope (optional) auto-unsubscribe on $scope
          '$destroy' event

      @return [Array] returns plain [] with processed contents
      ###
      constructor: (source, filter, options, scope) ->
        if source instanceof Array or typeof source isnt 'object'
          source = _: source # unnamed source, triggers using direct map

        source_count = 0
        for source_name, source_list of source
          unless source_list instanceof Array and source_list.options and
          source_list.events instanceof EventEmitter
            argument_type_error
              source: source_list
              name:   source_name
              required: 'List'

          source_count += 1

          define_value source, source_name, source_list, 0, 1
        Object.freeze source

        if source._
          if source_count > 1
            argument_type_error
              source:   source
              conflict: 'Can not have unnamed ("_") and named sources mixed'

        if is_object filter
          scope   = options
          options = filter
          filter  = null

        unless options?
          options = {}
        unless is_object options
          argument_type_error {options, argument: 3, required: 'object'}

        if $rootScope.isPrototypeOf options
          scope = options
          options = {}

        if scope?
          unless $rootScope.isPrototypeOf scope
            argument_type_error {scope, required: '$rootScope descendant'}

        if filter
          options.filter = filter

        list = []

        # adds ._tracker
        new ArrayTracker list,
          set: (index, value, next, set_type) ->
            if set_type is 'external' and
            (record = list._tracker.store[index]) instanceof Record
              record._replace value
            else
              next()
            return

        define_value list, '_origFn', {}

        # copy methods from ListMask:: to the array instance
        for key, value of @constructor.prototype
          if value? and key isnt 'constructor'
            list._origFn[key] = list[key]
            define_value list, key, value

        # disable methods that change contents
        # TODO: check what to do with: 'copyWithin', 'fill'
        for key in ['pop', 'push', 'reverse', 'shift', 'sort', 'splice',
                    'unshift']
          list._origFn[key] = list[key]
          define_value list, key

        define_value list, 'events', new EventEmitter

        define_value list, 'options', options

        define_value list, 'source', source

        ListMask.registerFilter   list
        ListMask.registerSplitter list

        # sets @_mapper, @idMap and @pseudoMap
        ListMapper.register list
        sources = list._mapper._sources

        if scope
          define_value list, SCOPE_UNSUBSCRIBER, scope.$on '$destroy', ->
            delete list[SCOPE_UNSUBSCRIBER]
            list.destroy()

        unsubscriber = null
        flat_sources = []
        for source_info in sources
          if source_info.source in flat_sources
            error.Value
              sources:  sources
              conflict: 'Source can not be referenced twice to keep list unique'

          flat_sources.push source_info.source
          do (source_info) ->
            unsub = source_info.source.events.on 'update', (info) ->
              ListMask.update.call list, info, source_info.names

            if unsubscriber
              unsubscriber.add unsub
            else
              unsubscriber = unsub

            # if any of the sources gets destroyed, this list gets destroyed
            unsubscriber.add source_info.source.events.on 'destroy', ->
              list.destroy()

        define_value list, '_sourceUnsubscriber', unsubscriber

        # sets both .sorter and .options.sorter
        ListSorter.register list, options.sorter

        # add initial set of data
        for source_info in sources
          for record in source_info.source when list.filter record
            if record._parent.idProperty?
              list._mapper.add record, source_info.names
            ListMask.add list, record

        return list

      ###
      Unsubscribes from list, destroy all properties and freeze
      See: {List#destroy}

      @event 'destroy' sends out message pre-destruction

      @return [boolean] false if the object was already destroyed
      ###
      destroy: ->
        List::destroy.call @

      ###
      Record filter logic that defines the list mask

      @note This is Getter/setter for function. Function should be assigned at
        init time (as part of the constructor arguments, like this:
        `new ListMask src_list, filter_fn`) and can be changed run-time by
        assigning a new function to either list_mask.filter or
        list_mask.options.filter.

      @note list_mask.filter or list_mask.options.filter have the same
        getter/setter

      @param [Record] record Record instance to check

      @return [boolean] indicates if record should be on the masked list
      ###
      filter: (record) -> #DOC-ONLY#

      ###
      Optional list auto-sorter logic, see: {ListSorter}

      @note This is Getter/setter for function or undefined. Will start as
        undefined by default. Function can be assigned at init time (as part of
        options, like: `new ListMask src_list, filter_fn, {sorter: fn}`) or in
        run-time by assigning function or null/undefined to either
        list_mask.sorter or list_mask.options.sorter.

      @note list_mask.sorter or list_mask.options.sorter have the same
        getter/setter

      @param [Record] record_a Record instance to compare
      @param [Record] record_b Record instance to compare

      @return [number] <0, 0, >0 indicates sort relation between records A and B
      ###
      sorter: (record_a, record_b) -> #DOC-ONLY#

      ###
      Optional record splitter logic

      @note This is Getter/setter for function or undefined. Will start as
        undefined by default. Function can be assigned at init time (as part
        of options, like: `new ListMask src_list, filter_fn, {splitter: fn}`) or
        in run-time by assigning function or null/undefined to either
        list_mask.splitter or list_mask.options.splitter.

      @note list_mask.splitter or list_mask.options.splitter have the same
        getter/setter

      @param [Record] record Record instance to check

      @return [Array<Record>|false] split records in array or anything else to
        indicate no splitting of record
      ###
      splitter: (record) -> #DOC-ONLY#

      ###
      Re-do filtering. Useful when external condtions change for the filter

      @return [Object] Actions desctription (or empty {} if nothing changed)
      ###
      update: ->
        action = {}
        list   = @
        mapper = list._mapper

        for source_info in mapper._sources
          source_names = source_info.names
          for record in source_info.source
            if mapped = record._parent.idProperty
              is_on = mapper.has record, null, source_names
            else
              is_on = record in list
            if list.filter record
              unless is_on
                if mapped
                  mapper.add record, source_names
                ListMask.add list, record
                (action.add ?= []).push record
            else if is_on
              if mapped
                mapper.del record, null, source_names
              (action.cut ?= []).push record

        if action.cut
          ListMask.cut list, action.cut

        ListMask.rebuild list

        if action.add or action.cut
          list.events.emit 'update', {node: list, action}

        action


      ###
      Helper function that adds element to list Array in a sort-sensitive way
      when needed

      @param [Array] list container array instance generated by ListMask
      @param [Record] record Item to inject

      @return [undefined]
      ###
      @add: (list, record) ->
        records = ListMask.splitterWrap list, record
        if list.sorter # sorted (insert to position)
          for item in records
            pos = list.sorter.position item
            list._origFn.splice.call list, pos, 0, item
        else
          list._origFn.push.apply list, records
        return

      ###
      Helper function that removes elements from list Array

      @param [Array] list container array instance generated by ListMask
      @param [Array] records Record items to cut

      @return [undefined]
      ###
      @cut: (list, records) ->
        tmp_container = []
        while record = list._origFn.pop()
          target = record._original or record
          unless target in records
            tmp_container.push record
        if tmp_container.length
          tmp_container.reverse()
          list._origFn.push.apply list, tmp_container
        return

      ###
      Helper function that empties and reloads masked list Array instance from
      source (used when source changes are untrackable or ambiguous).

      @param [Array] list container array instance generated by ListMask

      @return [undefined]
      ###
      @rebuild: (list) ->
        util.empty list
        for source_info in list._mapper._sources
          for record in source_info.source
            if list.filter record
              list._origFn.push.apply list, ListMask.splitterWrap list, record
        return

      ###
      Helper function that registers a filter function on the {ListMask} object
      (and its .options object)

      @param [ListMask] list Reference to list mask

      @return [undefined]
      ###
      @registerFilter: (list) ->
        default_fn = (-> true)

        unless filter = list.options.filter
          filter = default_fn

        filter_get = ->
          filter

        filter_set = (filter_function) ->
          unless filter_function
            filter_function = default_fn

          unless typeof filter_function is 'function'
            error.Type {filter_function, required: 'function'}
          filter = filter_function
          list.update()

        define_get_set list,         'filter', filter_get, filter_set, 1
        define_get_set list.options, 'filter', filter_get, filter_set, 1

        return

      ###
      Helper function that registers a splitter function function on the
      {ListMask} object (and its .options object)

      @param [ListMask] list Reference to list mask

      @return [undefined]
      ###
      @registerSplitter: (list) ->
        default_fn = (-> false)

        unless splitter = list.options.splitter
          splitter = default_fn

        splitter_get = ->
          splitter

        splitter_set = (splitter_function) ->
          unless splitter_function
            splitter_function = default_fn

          unless typeof splitter_function is 'function'
            error.Type {splitter_function, required: 'function'}
          splitter = splitter_function
          list.update()

        define_get_set list,         'splitter', splitter_get, splitter_set, 1
        define_get_set list.options, 'splitter', splitter_get, splitter_set, 1

        return

      ###
      Helper function to wrap splitter function and turn them into an Array
      instance (either with the original record only, or all the masked record
      children)

      @param [Array] list Array instance generated by {ListMask}
      @param [Record] record Record instance to match and optionally split

      @return [Array]
      ###
      @splitterWrap: (list, record) ->
        if (result = list.splitter record) and result instanceof Array
          record_masks = [] # split record masks
          for info in result
            unless is_object info
              error.Type
                splitter:    list.splitter
                description: 'If Array is returned, all elements must be ' +
                              'objects with override data'
            record_mask = Object.create record
            for key of record
              do (key, record) ->
                getter = ->
                  record[key]
                setter = (value) ->
                  record[key] = value
                define_get_set record_mask, key, getter, setter, 1
            for key, value of info
              define_value record_mask, key, value, 0, 1
            define_value record_mask, '_original', record
            record_masks.push record_mask
          return record_masks
        [record]

      ###
      Helper function that handles all kinds of event mutations coming from the
      parent (source) {List}

      Action types: 'add', 'cut', 'update'
      Targets and sources may or may not be or had been on filtered list,
      so this function may or may not transform (or drop) the event before it
      emits to its own listeners.

      @param [Object] info Event information object
      @param [string] source_names name of the source list ('_' for unnamed)

      @event 'update' See {List#_recordChange}, {List#add} and {List#remove} for
        possible event emission object descriptions

      @return [undefined]
      ###
      @update: (info, source_names) ->
        action   = null
        cut      = []
        list     = @
        incoming = info.action
        mapper   = list._mapper

        add_action = (name, info) ->
          ((action ?= {})[name] ?= []).push info

        is_on = (map_id, pseudo_id, record) ->
          if record._parent.idProperty
            return [1, mapper.has map_id, pseudo_id, source_names]
          else
            return [0, record in list]

        cutter = (map_id, pseudo_id, record) ->
          [mapped, was_on] = is_on map_id, pseudo_id, record
          if was_on
            add_action 'cut', record
            cut.push record
            if mapped
              mapper.del map_id, pseudo_id, source_names
          return

        find_and_add = (map_id, pseudo_id, record) ->
          [mapped, was_on] = is_on map_id, pseudo_id, record
          if mapped and not was_on
            mapper.add record, source_names
          was_on

        delete_if_on = (map_id, pseudo_id) ->
          [mapped, was_on] = is_on map_id, pseudo_id, record
          if mapped and was_on
            mapper.del map_id, pseudo_id, source_names
          was_on

        if incoming.cut
          for record in incoming.cut
            cutter record._id, record._pseudo, record

        if incoming.add
          for record in incoming.add when list.filter record
            find_and_add record._id, record._pseudo, record
            ListMask.add list, record
            add_action 'add', record

        if incoming.update
          for info in incoming.update
            {record, info, merge, move, source} = info
            from = to = null
            if remapper = merge or move
              {from, to} = remapper

            if list.filter record # update or add
              source_found = from and delete_if_on from.idMap, from.pseudoMap

              if to
                target_found = find_and_add to.idMap, to.pseudoMap, record
              else
                target_found = find_and_add record._id, record._pseudo, record

              if source_found and target_found
                add_action 'update', {record, info, merge: remapper, source}
                cut.push source
              else if source_found
                add_action 'update', {record, info, move: remapper}
              else if target_found
                update_info = {record}
                for key, value of {info, source} when value?
                  update_info[key] = value
                add_action 'update', update_info
              else
                ListMask.add list, record
                add_action 'add', record
            else # remove if found
              if merge
                cutter from.idMap, from.pseudoMap, source
                cutter to.idMap, to.pseudoMap, record
              else if move
                cutter from.idMap, from.pseudoMap, record
              else
                cutter record._id, record._pseudo, record

        unless list.sorter
          # NOTE: reversing and re-sorting is done here for received 'reverse'
          # and 'sort' action
          ListMask.rebuild list
        else if cut.length
          ListMask.cut list, cut

        if action
          list.events.emit 'update', {node: list, action}

        return
]
