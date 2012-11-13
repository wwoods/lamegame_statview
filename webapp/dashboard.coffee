define [ 'cs!lib/ui', 'cs!graph', 'css!dashboard' ], (ui, Graph) ->
    class DashboardCell extends ui.Base
        constructor: (child) ->
            super('<div class="dashboard-cell"></div>')
            @append(child)


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

            @columns = columns
            @ratio = 0.618 # height / width

            # Let us get added to dom, since we'll need a valid width
            ui.setZeroTimeout () =>
                @app = ui.fromDom(@closest('.stats-app'))

                @_createNew = new DashboardNew()
                @_createNew.bind "click", () =>
                    @append(new Graph())
                @_createNew = @append(@_createNew)

                if definition?
                    for config in definition.graphs
                        @append(new Graph(config))


        append: (graph) ->
            ### Creates a cell to contain the graph and adds it to our view.

            Returns the new cell
            ###
            cell = new DashboardCell(graph)
            @_resizeCell(cell)
            # Window width can change on insert
            oSize = $(window).width()
            if graph instanceof Graph
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
            for cell in @children()
                @_resizeCell(ui.fromDom(cell))


        _resizeCell: (cell) ->
            w = @width() / @columns
            h = Math.min(w * @ratio, $(window).height() - @app.header.height())
            cell.css
                width: w
                height: h


    class Dashboard extends ui.Base
        constructor: (definition, columns = 2) ->
            super('<div class="dashboard"></div>')

            @container = new DashboardContainer(definition, columns).appendTo(@)

            $(window).resize () =>
                @container.resize()


        changeColumns: (i) ->
            @container.columns += i
            if @container.columns < 1
                @container.columns = 1
            @container.resize()


        getDefinition: () ->
            # Get the definition of this dashboard to save out
            result =
                graphs: []
            for g in @container.children()
                # Look at second-level child, since first is "cell" object
                g = ui.fromDom($(g).children())
                if not (g instanceof Graph)
                    continue
                result.graphs.push($.extend({}, g.config))
            return result


        getTimeAmt: () ->
            return ui.fromDom('.stats-header').timeAmt.val()


        getTimeBasis: () ->
            return 'now'


        refresh: () ->
            @container.refresh()
            

