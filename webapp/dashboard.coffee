define [ 'cs!lib/ui', 'cs!graph', 'css!dashboard' ], (ui, Graph) ->
    class DashboardCell extends ui.Base
        constructor: (child) ->
            super('<div class="dashboard-cell"></div>')
            @append(child)
            
            
        remove: () ->
            @trigger("needs-save")
            super()


    class DashboardNew extends ui.Base
        # Placeholder widget - click to add a graph
        constructor: () ->
            super('<div class="graph dashboard-new"></div>')
            @append('<table style="width:100%;height:100%;text-align:center">
                    <tr>
                      <td style="vertical-align:middle;">Add New...</td>
                    </tr></table>')


    class DashboardContainer extends ui.DragContainer
        constructor: (definition, columns) ->
            super
                root: '<div class="dashboard-container"></div>'
                handleSelector: '.controls-collapse'
                afterDrag: () => @trigger("needs-save")
                isLinear: false

            @columns = columns
            @ratio = 0.618 # height / width

            # Let us get added to dom, since we'll need a valid width and a
            # valid reference to our @dashboard.
            ui.setZeroTimeout () =>
                @app = ui.fromDom(@closest('.stats-app'))
                @dashboard = @uiClosest('.dashboard')

                @_createNew = new DashboardNew()
                @_createNew.bind "click", () =>
                    @append(new Graph(null, @dashboard))
                @_createNew = @append(@_createNew)

                if definition?
                    console.log(definition)
                    for config in definition.graphs
                        @append(new Graph(config, @dashboard))
                    @dashboard.setTimeAmtIfBlank(definition.timeAmt)
                    @dashboard.setSmoothAmtIfBlank(definition.smoothAmt)


        append: (graph, insertAfter) ->
            ### Creates a cell to contain the graph and adds it to our view.

            Returns the new cell
            ###
            cell = new DashboardCell(graph)
            @_resizeCell(cell)
            # Window width can change on insert
            oSize = $(window).width()
            if graph instanceof Graph
                if insertAfter?
                    if not insertAfter.is('.dashboard-cell')
                        insertAfter = insertAfter.closest('.dashboard-cell')
                    insertAfter.after(cell)
                else
                    @_createNew.before(cell)
            else
                # Create new placeholder
                super(cell)
            ui.setZeroTimeout () =>
                # In setZeroTimeout since the scrollbar is not added until
                # the window refreshes (at least in chrome)
                if oSize != $(window).width()
                    @resize()
            return cell


        refresh: () ->
            # Refresh all graphs
            for cell in @children()
                graph = ui.fromDom($(cell).children())
                if graph instanceof Graph
                    graph.update()


        resize: () ->
            # Resize all graphs on window resize
            owidth = @children(':first').width()
            for cell in @children()
                @_resizeCell(ui.fromDom(cell))
            nwidth = @children(':first').width()
            if owidth != nwidth
                @refresh()


        _resizeCell: (cell) ->
            # Subtract 1 to ensure that the number of columns is accurate
            if not cell?
                return
            w = (@width() - 1) / @columns
            h = Math.min(w * @ratio, $(window).height() - @app.header.height())
            cell.css
                width: w
                height: h
                


    class Dashboard extends ui.Base
        constructor: (definition, columns = 2) ->
            super('<div class="dashboard"></div>')

            @container = new DashboardContainer(definition, columns).appendTo(@)
            @_savedDefinition = definition
            
            owidth = $(window).width()
            mySizer = () =>
                if @closest('body').length == 0
                    # No longer in dom
                    $(window).unbind("resize", mySizer)
                    
                nwidth = $(window).width()
                if nwidth != owidth
                    owidth = nwidth
                    @container.resize()
            $(window).resize(mySizer)


        changeColumns: (i) ->
            @container.columns = i
            @container.resize()
            
            
        getAllowedGroupValues: () ->
            # Get the global filter; returns a dict of { groupName: [ values ] }
            # for groups that have filters.
            return ui.fromDom('.stats-header').globalFilters


        getAutoRefresh: () ->
            return 300


        getDefinition: () ->
            # Get the definition of this dashboard to save out
            result =
                graphs: []
                timeAmt: @getTimeAmt()
                smoothAmt: @getSmoothAmt()
            for g in @container.children()
                # Look at second-level child, since first is "cell" object
                g = ui.fromDom($(g).children())
                if not (g instanceof Graph)
                    continue
                result.graphs.push($.extend({}, g.config))
            return result
            
            
        getSanitize: () ->
            return ui.fromDom('.stats-header').sanitize


        getSavedDefinition: () ->
            return @_savedDefinition
            
            
        getSmoothAmt: () ->
            return ui.fromDom('.stats-header').smoothAmt.val()


        getTimeAmt: () ->
            return ui.fromDom('.stats-header').timeAmt.val()


        getTimeBasis: () ->
            return 'now'


        getUtcDates: () ->
            return ui.fromDom('.stats-header').utcDates


        refresh: () ->
            @container.refresh()
            

        setTimeAmt: (amt) ->
            ui.fromDom('.stats-header').timeAmt.val(amt)


        setTimeAmtIfBlank: (amt) ->
            ta = ui.fromDom('.stats-header').timeAmt
            if ta.val() == ''
                if amt
                    ta.val(amt)
                else
                    ta.val('1 week')


        setSavedDefinition: (definition) ->
            @_savedDefinition = definition


        setSmoothAmt: (amt) ->
            ui.fromDom('.stats-header').smoothAmt.val(amt)


        setSmoothAmtIfBlank: (amt) ->
            ta = ui.fromDom('.stats-header').smoothAmt
            if ta.val() == ''
                if amt
                    ta.val(amt)
                else
                    ta.val('6 hours')
