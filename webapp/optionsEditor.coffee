define ["cs!lib/ui", "css!optionsEditor"], (ui) ->
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


    class OptionsEditor extends ui.Dialog
        constructor: (options) ->
            ### filters is a dict: { group: [ allowed values ] }
            ###
            @options = options
            @sanitizeHolder = options.sanitizeHolder
            @filters = options.filters
            @_initSettings = 
                filters: $.extend(true, {}, @filters)
                sanitize: @sanitizeHolder.sanitize
            @statsController = options.statsController
            
            body = $('<div class="options-editor"></div>')
            body.append('<div class="header">Filters</div>')
            
            @filterRows = $('<table class="filter-rows"></table>')
                .appendTo(body)
            allGroups = []
            for g of @statsController.groups
                allGroups.push(g)
            allGroups.sort()
            for g in allGroups
                @filterRows.append(new FilterRow(g, @))
                
            body.append('<div class="header">Misc Options</div>')
            sanDiv = $('<div></div>').appendTo(body)
            @sanitizer = $('<input type="checkbox" />').appendTo(sanDiv)
            if @sanitizeHolder.sanitize
                @sanitizer.attr('checked', true)
            sanTip = $("<span>Sanitize graphs</span>").appendTo(sanDiv)
            sanTip.add(@sanitizer)
                .bind("mouseover", (e) -> ui.Tooltip.show(e, """Sanitize the 
                        range
                        of graphs when graphing large values - for instance,
                        if 99% of values are of the range 10, but there's
                        a few values that are in the range of 1000000, then
                        clamp the graph to something like [0, 12] and "flatten"
                        the extreme point.  The tooltip will still show real
                        values."""))
                .bind("mouseout", () -> ui.Tooltip.hide())
            
            super(body: body)
            
            
        remove: () ->
            ### Save our filters
            ###
            @sanitizeHolder.sanitize = @sanitizer.is(':checked')
            @_refreshFilters()
            newSettings =
                filters: @filters
                sanitize: @sanitizeHolder.sanitize
            if not $.compareObjs(newSettings, @_initSettings)
                if @options.onChange?
                    @options.onChange()
            super()
            
            
        _refreshFilters: () ->
            ### Refresh @filters from gui
            ###
            for f in $('tr', @filterRows)
                f = ui.fromDom(f)
                f.saveFilter()

