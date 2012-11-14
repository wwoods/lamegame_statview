define [ 'cs!lib/ui', 'css!controls' ], (ui) ->
    class Controls extends ui.Base
        constructor: (graph, autoExpand) ->
            super('<div class="controls"></div>')
            self = @

            @_graph = graph
            @_statsController = graph._statsController

            @_expandCollapse = $('<div class="controls-collapse"></div>')
            @append(@_expandCollapse)
            @_content = $('<div class="controls-content"></div>')
            @append(@_content)

            @bind('click', () =>
                # Stop it from affecting graph
                return false
            )

            @_expandCollapse.bind('click', () =>
                @_content.show()
                
                @expr.trigger("change")
                # And add the groups we're actually using
                for grp in options.groups
                    addGroupFilter(grp[0], grp[1])
                    
                ui.Shade.show(@_content, hide: () =>
                    ok.trigger("click")
                    @_content.hide()
                )
            )

            timeDiv = $('<div>Show last </div>')
            timeDivAmt = $('<input type="text" />').appendTo(timeDiv)
            # COMMENTED!  Dashboard has an overall time, no need for this
            #@_content.append(timeDiv)

            @type = new ui.ListBox()
            @type.addOption "area-zoom", "Area Zoomed"
            @type.addOption "area", "Area"
            @_content.append(@type)

            @_content.append("Title: ")
            @title = $('<input type="text" />').appendTo(@_content)
            @title.css
                width: '200px'
            @title.val('(unnamed)')

            @_content.append('<br />')

            lb = new ui.ListBox(multiple: true)
            @_content.append(lb)
            for name of @_statsController.stats
                lb.addOption name
            lb.delegate "option", "click", ->
                # Not fat arrow, need this from event
                self.expr.val(self.expr.val() + $(this).val())
                self.expr.trigger('change')
                self.expr.focus()

            exprDiv = $('<div>Expression</div>').appendTo(@_content)
            @expr = $('<textarea></textarea>').appendTo(exprDiv)
            @_statsFound = []
            @expr.bind "change keyup", =>
                # Re-calculate width of field
                fake = $('<div style="display:inline-block;white-space:nowrap;"></div>')
                fake.text(@expr.val())
                fake.appendTo('body')
                w = fake.width()
                fake.remove()
                @expr.width(Math.min(250, Math.max(100, w)) + 'px')
                @expr.height(1)
                @expr.height(Math.max(20, @expr[0].scrollHeight))
                @updateExpression(@expr.val())

            @groupsActive = new ui.Base("<div></div>")
            @groupsActive.delegate "div", "click", ->
                $(this).remove()

            @_content.append "<div>Groups</div>"
            @_content.append @groupsActive
            @_content.append "<div>Groups Available</div>"
            @groupList = new ui.ListBox(multiple: true)
            @_content.append @groupList
            addGroupFilter = (grp, filter = '') =>
                # Add a filter to the UI.  Done through either clicking group
                # in list, or during load
                g = $("<div></div>").text(grp).appendTo(@groupsActive)
              
                # Stop click from removing the row
                $("<input class=\"regex\" type=\"text\" />").bind("click", ->
                    false
                ).appendTo(g).val(filter)
                
            @groupList.delegate "option", "click", ->
                # Don't use fat arrow, this refers to obj clicked
                addGroupFilter($(this).val())

            smootherDiv = $("<div></div>").appendTo(@_content)
            smootherDiv.append "Smooth hours: "
            smoother = $("<input type=\"text\" />").appendTo(smootherDiv)
            ok = new ui.Base("<input type=\"button\" value=\"Refresh\" />")
            @_content.append ok

            cloner = new ui.Base('<input type="button" value="Clone" />')
            cloner.css
                position: 'relative'
                float: 'right'
            @_content.append(cloner)
            cloner.bind "click", () =>
                Graph = require("cs!graph")
                @uiClosest('.dashboard-container').append(
                        new Graph(@_graph.config), @)
                ui.Shade.hide()
            deleter = new ui.Base('<input type="button" value="Delete" />')
            deleter.css
                position: 'relative'
                float: 'right'
            @_content.append(deleter)
            deleter.bind "click", () =>
                @uiClosest('.dashboard-cell').remove()

            # Populate initial fields from graph
            options = @_graph.config
            @title.val(options.title)
            @expr.val(options.expr)
            smoother.val(options.smoothOver)
            timeDivAmt.val(options.timeAmt)
            # Wait to trigger expr change and update groups available until
            # we're in the dom and visible (in @_expandCollapseButton)

            # Bind refresh button
            ok.bind 'click', () =>
                stat = @_statsController.stats[lb.val()]
                groups = []
                @groupsActive.children().each ->
                    filter = $(".regex", $(this)).val()
                    groups.push [$(this).text(), filter]

                options =
                    title: @title.val()
                    type: @type.val()
                    stats: @_statsFound
                    expr: @expr.val()
                    groups: groups
                    smoothOver: smoother.val()
                    timeAmt: timeDivAmt.val()
                    autoRefresh: 300

                @_graph.update options

            @_content.hide()
            if autoExpand
                @_expandCollapse.trigger("click")


        updateExpression: (expr) ->
            @groupsActive.empty()
            @groupList.reset()

            @_statsFound = @_graph.parseStats(expr)
            for stat in @_statsFound
                i = 0
                m = stat.groups.length
                while i < m
                    if (
                            $('[value=' + stat.groups[i] + ']', @groupList).length == 0
                            )
                        @groupList.addOption stat.groups[i]
                    i++

