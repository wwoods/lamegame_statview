define ["cs!lib/ui"], (ui) ->
    class FilterRow extends ui.Base
        constructor: (group, editor) ->
            @group = group
            @editor = editor
            @sc = @editor.statsController
            
            super('<tr class="filter-row"></tr>')
            
            @groupLabel = new ui.Base('<td></td>')
                .text(group)
                .appendTo(@)
                
            @values = new ui.ListBox(multiple: true)
                .appendTo($('<td></td>').appendTo(@))
            for val in @sc.groups[@group]
                @values.addOption(val)
                
            selected = @editor.filters[@group]
            if selected?
                @values.val(@editor.filters[@group])
                
            @values.multiselect(
                    selectedText: (checked, total) =>
                        if checked == total
                            return "displaying all"
                        else
                            return "displaying #{ checked } of #{ total }"
                    noneSelectedText: "displaying all"
                )
                .multiselectfilter()
            
            
        saveFilter: () ->
            ### Update the filter for this filterRow, or delete the element
            if we shouldn't filter.
            ###
            count = @values.children().length
            selected = @values.val() or []
            if count == selected.length or selected.length == 0
                delete @editor.filters[@group]
            else
                @editor.filters[@group] = selected
                
                
        _refreshValues: () ->
            @values.empty()
            for v in @sc.groups[@group.val()]
                @values.addOption(v)


    class FilterEditor extends ui.Dialog
        constructor: (options) ->
            ### filters is a dict: { group: [ allowed values ] }
            ###
            @options = options
            @filters = options.filters
            @_initFilters = $.extend(true, {}, @filters)
            @statsController = options.statsController
            
            body = $('<div class="filter-editor"></div>')
            body.append("<div>Filters</div>")
            
            @filterRows = $('<table class="filter-rows"></table>')
                .appendTo(body)
            allGroups = []
            for g of @statsController.groups
                allGroups.push(g)
            allGroups.sort()
            for g in allGroups
                @filterRows.append(new FilterRow(g, @))
            
            super(body: body)
            
            
        remove: () ->
            ### Save our filters
            ###
            @_refreshFilters()
            if not $.compareObjs(@filters, @_initFilters) and @options.onChange
                @options.onChange()
            super()
            
            
        _refreshFilters: () ->
            ### Refresh @filters from gui
            ###
            for f in $('tr', @filterRows)
                f = ui.fromDom(f)
                f.saveFilter()

