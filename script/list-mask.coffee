
ksc.factory 'ksc.ListMask', [
  '$rootScope', 'ksc.EventEmitter', 'ksc.List', 'ksc.ListMapper',
  'ksc.ListSorter', 'ksc.error', 'ksc.util',
  ($rootScope, EventEmitter, List, ListMapper,
   ListSorter, error, util) ->

    SCOPE_UNSUBSCRIBER = '_scopeUnsubscriber'

    argument_type_error = error.ArgumentType

    define_get_set = util.defineGetSet
    define_value   = util.defineValue
    is_object      = util.isObject

    array_push = Array::push

    ###
    Helper function that adds element to list Array in a sort-sensitive way when
    needed

    @param [Array] list container array instance generated by ListMask
    @param [Record] record Item to inject

    @return [undefined]
    ###
    add_to_list = (list, record) ->
      records = splitter_wrap list, record
      if list.sorter # sorted (insert to position)
        for item in records
          pos = list.sorter.position item
          Array::splice.call list, pos, 0, item
      else
        array_push.apply list, records
      return

    ###
    Helper function that removes elements from list Array

    @param [Array] list container array instance generated by ListMask
    @param [Array] records Record items to cut

    @return [undefined]
    ###
    cut_from_list = (list, records) ->
      tmp_container = []
      while record = Array::pop.call list
        target = record._original or record
        unless target in records
          tmp_container.push record
      if tmp_container.length
        tmp_container.reverse()
        array_push.apply list, tmp_container
      return


    rebuild_list = (list) ->
      util.empty list
      for source_info in list._mapper._sources
        for record in source_info.source
          if list.filter record
            array_push.apply list, splitter_wrap list, record
      return

    ###
    Helper function that registers a filter function on the {ListMask} object
    (and its .options object)

    @param [ListMask] list Reference to list mask

    @return [undefined]
    ###
    register_filter = (list) ->
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
    register_splitter = (list) ->
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
    splitter_wrap = (list, record) ->
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
    Masked list that picks up changes from parent {List} instance(s)
    Features:
    - may be a composite of multiple named parents/sources to combine different
    kinds of records in the list. That also addes namespaces to .map and .pseudo
    containers like: .map.sourcelistname
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

            list.map[1].x = 'xxx' # should remove item form sublist as it does
                                  # not meet the filter_fn requirement any more

            console.log sublist # [{id: 2, x: 'baa'}]

    @note Do not forget to manage the lifecycle of lists to prevent memory leaks
    @example
            # You may tie the lifecycle easily to a controller $scope by
            # just passing it to the constructor as last argument (arg #3 or #4)
            sublist = new ListMask list, filter_fn, $scope

            # you can destroy it at any time though:
            sublist.destroy()

    May also get two or more {List}s to form composite lists.
    In this case, sources must be named so that .map.name and .pseudo.name
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

            list.map.one[1].x = 'xxx' # removes item form sublist as it does not
                                      # meet the filter_fn requirement any more

            console.log sublist # [{id: 2, x: 'baa'}, {id2: 1, x: 'a'}]

    A splitter function may also be added to trigger split records appearing in
    the list mask (but not on .map or .pseudo where the original record would
    appear only). Split records are masks of records that have the same
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
      _mapper: null

      # @property [EventEmitter] reference to related event-emitter instance
      events: null

      ###
      @property [function] function with signiture `(record) ->` and boolean
        return value indicating if record should be in the filtered list
      ###
      filter: null

      # @property [object] hash map of records (keys being record ._id values)
      map: null

      # @property [object] filtered list related options
      options: null

      # @property [object] hash map of records without ._id keys
      pseudo: null

      # @property [ListSorter] (optional) list auto-sort logic see: {ListSorter}
      sorter: null

      # @property [object] reference to parent list
      source: null

      ###
      @property [function] function with signiture `(record) ->` that returns
        an Array of overrides to split records or anything else to indicate no
        splitting of record
      ###
      splitter: null


      ###
      Creates a vanilla Array instance (e.g. []), disables methods like
      pop/shift/push/unshift since thes are supposed to be used on the source
      (aka parent) list only

      @note If a single {List} or {ListMask} source/parent is provided as first
        argument, .map and .pseudo references will work just like in {List}. If
        object with key-value pairs provided (values being sources/parents),
        records get mapped like .map.keyname[id] and .pseudo.keyname[pseudo_id]

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

          define_value source, source_name, source_list
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

        # copy methods from ListMask:: to the array instance
        for key, value of @constructor.prototype
          define_value list, key, value

        # disable methods that change contents
        for key in ['copyWithin', 'fill', 'pop', 'push', 'reverse', 'shift',
                    'sort', 'splice', 'unshift']
          if list[key]
            define_value list, key

        define_value list, 'events', new EventEmitter

        define_value list, 'options', options

        define_value list, 'source', source

        register_filter   list
        register_splitter list

        # sets @_mapper, @map and @pseudo
        if source.options.record.idProperty
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
          for record in source_info.source
            if list.filter record
              list._mapper?.add record, source_info.names
              add_to_list list, record

        return list

      ###
      Unsubscribes from list, destroy all properties and freeze
      See: {List#destroy}

      @event 'destroy' sends out message pre-destruction

      @return [boolean] false if the object was already destroyed
      ###
      destroy: List::destroy

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
            is_on = mapper.has record, null, source_names
            if list.filter record
              unless is_on
                mapper.add record, source_names
                add_to_list list, record
                (action.add ?= []).push record
            else if is_on
              mapper.del record, null, source_names
              (action.cut ?= []).push record

        if action.cut
          cut_from_list list, action.cut

        rebuild_list list

        if action.add or action.cut
          list.events.emit 'update', {node: list, action}

        action


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

        cutter = (map_id, pseudo_id, record) ->
          if mapper.has map_id, pseudo_id, source_names
            add_action 'cut', record
            cut.push record
            mapper.del map_id, pseudo_id, source_names

        find_and_add = (map_id, pseudo_id, record) ->
          unless is_on = mapper.has map_id, pseudo_id, source_names
            mapper.add record, source_names
          is_on

        delete_if_on = (map_id, pseudo_id) ->
          if is_on = mapper.has map_id, pseudo_id, source_names
            mapper.del map_id, pseudo_id, source_names
          is_on

        if incoming.cut
          for record in incoming.cut
            cutter record._id, record._pseudo, record

        if incoming.add
          for record in incoming.add when list.filter record
            find_and_add record._id, record._pseudo, record
            add_to_list list, record
            add_action 'add', record

        if incoming.update
          for info in incoming.update
            {record, info, merge, move, source} = info
            from = to = null
            if remapper = merge or move
              {from, to} = remapper

            if list.filter record # update or add
              source_found = from and delete_if_on from.map, from.pseudo

              if to
                target_found = find_and_add to.map, to.pseudo, record
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
                add_to_list list, record
                add_action 'add', record
            else # remove if found
              if merge
                cutter from.map, from.pseudo, source
                cutter to.map, to.pseudo, record
              else if move
                cutter from.map, from.pseudo, record
              else
                cutter record._id, record._pseudo, record

        unless list.sorter
          # NOTE: reversing and re-sorting is done here for received 'reverse'
          # and 'sort' action
          rebuild_list list
        else if cut.length
          cut_from_list list, cut

        if action
          list.events.emit 'update', {node: list, action}

        return
]
