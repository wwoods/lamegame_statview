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
                @_content.toggle()
            )

            timeDiv = $('<div>Show last </div>')
            timeDivAmt = $('<input type="text" />').appendTo(timeDiv)
            # COMMENTED!  Dashboard has an overall time, no need for this
            #@_content.append(timeDiv)

            lb = new ui.ListBox(multiple: true)
            @_content.append(lb)
            for name of @_statsController.stats
                lb.addOption name

            exprDiv = $('<div>Expression</div>').appendTo(@_content)
            @expr = $('<input type="text" />').appendTo(exprDiv)
            lb.delegate "option", "click", ->
                # Not fat arrow, need this from event
                self.expr.val(self.expr.val() + $(this).val())
                self.expr.trigger('change')

            @_statsFound = []
            @expr.bind "change keyup", =>
                # Re-calculate width of field
                fake = $('<div style="display:inline-block;white-space:nowrap;"></div>')
                fake.text(@expr.val())
                fake.appendTo('body')
                w = fake.width()
                fake.remove()
                @expr.width(Math.max(100, w) + 'px')
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

            deleter = new ui.Base('<input type="button" value="Delete" />')
            deleter.css
                position: 'absolute'
                right: '2px'
            @_content.append(deleter)
            deleter.bind "click", () =>
                @closest('.dashboard-cell').remove()

            # Populate initial fields from graph
            options = @_graph.config
            @expr.val(options.expr)
            smoother.val(options.smoothOver)
            timeDivAmt.val(options.timeAmt)
            # Update groups available
            @expr.trigger("change")
            # And add the groups we're actually using
            for grp in options.groups
                addGroupFilter(grp[0], grp[1])

            # Bind refresh button
            ok.bind 'click', () =>
                stat = @_statsController.stats[lb.val()]
                groups = []
                @groupsActive.children().each ->
                    filter = $(".regex", $(this)).val()
                    groups.push [$(this).text(), filter]

                options =
                    stats: @_statsFound
                    expr: @expr.val()
                    groups: groups
                    smoothOver: smoother.val()
                    timeAmt: timeDivAmt.val()
                    autoRefresh: 300

                @_graph.update options

            if not autoExpand
                @_content.hide()


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

