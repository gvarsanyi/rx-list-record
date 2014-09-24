
app.factory 'ksc.ListFilter', [
  '$rootScope', 'ksc.EventEmitter', 'ksc.ListMapper', 'ksc.ListSorter',
  'ksc.error', 'ksc.util',
  ($rootScope, EventEmitter, ListMapper, ListSorter,
   error, util) ->

    SCOPE_UNSUBSCRIBER  = '_scopeUnsubscriber'
    SOURCE_UNSUBSCRIBER = '_sourceUnsubscriber'

    argument_type_error = error.ArgumentType

    define_value = util.defineValue

    array_push = Array::push

    ###
    Helper function that clears list elements

    @param [Array] list Array instance generated by ListFilter

    @return [undefined]
    ###
    empty_list = (list) ->
      while Array::pop.call(list) then
      return

    ###
    Helper function that adds element to list Array in a sort-sensitive way when
    needed

    @param [Array] list container array instance generated by ListFilter
    @param [Record] record Item to inject

    @return [undefined]
    ###
    add_to_list = (list, record) ->
      if list.sorter # sorted (insert to position)
        pos = list.sorter.position record
        Array::splice.call list, pos, 0, record
      else
        array_push.call list, record
      return

    ###
    Helper function that removes elements from list Array

    @param [Array] list container array instance generated by ListFilter
    @param [Array] records Record items to cut

    @return [undefined]
    ###
    cut_from_list = (list, records) ->
      tmp_container = []
      while record = Array::pop.call list
        unless record in records
          tmp_container.push record
      if tmp_container.length
        tmp_container.reverse()
        array_push.apply list, tmp_container
      return

    ###
    Filtered list that picks up changes from parent (source) {List} instance
    automatically but may have its own sorter.

    Adding to or removing from a filtered list is not allowed, all of those
    operations are supposed to happen on the parent list.

    This list also emits appropriate events on changes, just like {List} does.

    @example
            list = new List
            list.push {id: 1, x: 'aaa'}, {id: 2, x: 'baa'}, {id: 3, x: 'ccc'}

            filter_fn = (record) -> # filter to .x properties that have char 'a'
              String(record.x).indexOf('a') > -1

            sublist = new ListFilter list, filter_fn
            console.log sublist # [{id: 1, x: 'aaa'}, {id: 2, x: 'baa'}]

            list.map[1].x = 'xxx' # should remove item form sublist as it does
                                  # not meet the filter_fn requirement any more

            console.log sublist # [{id: 2, x: 'baa'}]

    @note Do not forget to manage the lifecycle of lists to prevent memory leaks
    @example
            # You may tie the lifecycle easily to a controller $scope by
            # just passing it to the constructor as last argument (arg #3 or #4)
            sublist = new ListFilter list, filter_fn, $scope

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

            sublist = new ListFilter {one: list1, two: list2}, filter_fn
            console.log sublist # [{id: 1, x: 'aaa'}, {id: 2, x: 'baa'},
                                #  {id2: 1, x: 'a'}]

            list.map.one[1].x = 'xxx' # removes item form sublist as it does not
                                      # meet the filter_fn requirement any more

            console.log sublist # [{id: 2, x: 'baa'}, {id2: 1, x: 'a'}]

    @author Greg Varsanyi
    ###
    class ListFilter

      # @property [ListMapper] helper object that handles references to records
      #   by their unique IDs (._id) or pseudo IDs (._pseudo)
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
      Creates a vanilla Array instance (e.g. []), disables methods like
      pop/shift/push/unshift since thes are supposed to be used on the source
      (aka parent) list only

      @param [List/Object] source reference(s) to parent {List}(s). If a single
        list is provided, .map and .pseudo references will be used just like in
        {List}. If names are provided, records get mapped like .map.listname[id]
        and .pseudo.listname[pseudo_id]
      @param [function] filter function with signiture `(record) ->` and boolean
        return value indicating if record should be in the filtered list
      @param [Object] options (optional) options for the filtered list
      @param [ControllerScope] scope (optional) auto-unsubscribe on $scope
        '$destroy' event

      @return [Array] returns plain [] with filtered contents
      ###
      constructor: (source, filter, options, scope) ->
        if source instanceof Array or typeof source isnt 'object'
          source = _: source # unnamed source, triggers using direct map

        source_count = 0
        for source_name, source_list of source
          source_count += 1
          unless source_list instanceof Array and source_list.options and
          source_list.events instanceof EventEmitter
            argument_type_error
              source: source_list
              name:   source_name
              required: 'List'

        if source._
          if source_count > 1
            argument_type_error
              source:   source
              conflict: 'Can not have unnamed ("_") and named sources mixed'

        unless typeof filter is 'function'
          argument_type_error {filter, argument: 2, required: 'function'}

        unless options?
          options = {}
        unless util.isObject options
          argument_type_error {options, argument: 3, required: 'object'}

        if $rootScope.isPrototypeOf options
          scope = options
          options = {}

        if scope?
          unless $rootScope.isPrototypeOf scope
            argument_type_error {scope, required: '$rootScope descendant'}

        list = []

        # copy methods from ListFilter:: to the array instance
        for key, value of @constructor.prototype
          define_value list, key, value, false, true

        # disable methods that change contents
        for key in ['push', 'unshift', 'pop', 'shift', 'splice', 'reverse',
                    'sort']
          define_value list, key, undefined

        define_value list, 'events', new EventEmitter, false, true

        filter_get = ->
          filter

        filter_set = (filter_function) ->
          unless typeof filter_function is 'function'
            error.Type {filter_function, required: 'function'}
          filter = filter_function
          list.update()

        util.defineGetSet list, 'filter', filter_get, filter_set, true

        define_value list, 'options', options

        define_value list, 'source', source, false, true

        # sets @_mapper, @map and @pseudo
        new ListMapper list

        if scope
          define_value list, SCOPE_UNSUBSCRIBER, scope.$on '$destroy', ->
            delete list[SCOPE_UNSUBSCRIBER]
            list.destroy()

        unsubscriber = null
        for source_name, source_list of source
          do (source_name) ->
            unsub = source_list.events.on 'update', (info) ->
              ListFilter.update.call list, info, source_name

            if unsubscriber
              unsubscriber.add unsub
            else
              unsubscriber = unsub

            # if any of the sources gets destroyed, this list gets destroyed
            unsubscriber.add source_list.events.on 'destroy', ->
              list.destroy()

        define_value list, SOURCE_UNSUBSCRIBER, unsubscriber

        # sets both .sorter and .options.sorter
        ListSorter.register list, options.sorter

        # add initial set of data
        for source_name, source_list of source
          for record in source_list when filter record
            list._mapper.add record, source_name
            add_to_list list, record

        return list

      ###
      Unsubscribes from list, destroy all properties and freeze

      @event 'destroy' sends out message pre-destruction

      @return [boolean] false if the object was already destroyed
      ###
      destroy: ->
        list = @

        if Object.isFrozen list
          return false

        list.events.emit 'destroy'

        list[SCOPE_UNSUBSCRIBER]?()

        list[SOURCE_UNSUBSCRIBER]?()

        empty_list list

        for key of list when key isnt 'destroy'
          delete list[key]

        delete list.options
        delete list[SOURCE_UNSUBSCRIBER]

        Object.freeze list
        true

      ###
      Re-do filtering. Useful when external condtions change for the filter

      @return [Object] Actions desctription (or empty {} if nothing changed)
      ###
      update: ->
        action = {}
        list   = @
        mapper = list._mapper

        for source_name, source_list of list.source
          for record in source_list
            is_on = mapper.has record, null, source_name
            if list.filter record
              unless is_on
                mapper.add record, source_name
                add_to_list list, record
                (action.add ?= []).push record
            else if is_on
              mapper.del record, null, source_name
              (action.cut ?= []).push record

        if action.cut
          cut_from_list list, action.cut

        if action.add or action.cut
          list.events.emit 'update', {node: list, action}

        action


      ###
      Helper function that handles all kinds of event mutations coming from the
      parent (source) {List}

      Action types: 'add', 'cut', 'update'
      Targets and sources may or may not should be or had been on filtered list,
      so this function may or may not transform (or drop) the event before it
      emits to its own listeners.

      @param [Object] info Event information object
      @param [string] source_name name of the source list ('_' for unnamed)

      @event 'update' See {List#_recordChange}, {List#add} and {List#remove} for
        possible event emission object descriptions

      @return [undefined]
      ###
      @update: (info, source_name) ->
        action    = null
        cut       = []
        list      = @
        filter_fn = list.filter
        incoming  = info.action
        mapper    = list._mapper

        add_action = (name, info) ->
          ((action ?= {})[name] ?= []).push info

        cutter = (map_id, pseudo_id, record) ->
          if mapper.has map_id, pseudo_id, source_name
            add_action 'cut', record
            cut.push record
            mapper.del map_id, pseudo_id, source_name

        find_and_add = (map_id, pseudo_id, record) ->
          unless is_on = mapper.has map_id, pseudo_id, source_name
            mapper.add record, source_name
          is_on

        delete_if_on = (map_id, pseudo_id) ->
          if is_on = mapper.has map_id, pseudo_id, source_name
            mapper.del map_id, pseudo_id, source_name
          is_on

        if incoming.cut
          for record in incoming.cut
            cutter record._id, record._pseudo, record

        if incoming.add
          for record in incoming.add when filter_fn record
            find_and_add record._id, record._pseudo, record
            add_to_list list, record
            add_action 'add', record

        if incoming.update
          for info in incoming.update
            {record, info, merge, move, source} = info
            from = to = null
            if remapper = merge or move
              {from, to} = remapper

            if filter_fn record # update or add
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
          empty_list list
          for source_name, source_list of list.source
            for record in source_list
              if mapper.has record, null, source_name
                array_push.call list, record
        else if cut.length
          cut_from_list list, cut

        if action
          list.events.emit 'update', {node: list, action}

        return
]
