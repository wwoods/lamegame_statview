define [ 'cs!lib/ui.base', 'cs!lib/ui/listbox' ], (UiBase, ListBox) ->
    class Controls extends UiBase
        constructor: (graph) ->
            self = @
            super('<div class="controls"></div>')

            @_graph = graph
            @_statsController = graph._statsController

            @_content = $('<div class="controls-content"></div>')
            @append(@_content)
            @_expandCollapse = $('<div class="controls-collapse"></div>')
            @append(@_expandCollapse)

            @bind('click', () =>
                # Stop it from affecting graph
                return false
            )

            @_expandCollapse.bind('click', () =>
                @_content.toggle()
            )

            timeDiv = $('<div>Show last </div>')
            timeDivAmt = $('<input type="text" />').appendTo(timeDiv)
            @_content.append(timeDiv)

            lb = new ListBox()
            @_content.append(lb)
            for name of @_statsController.stats
                lb.addOption name
            lb.bind "change", =>
                groupsActive.empty()
                groupList.reset()
                stat = @_statsController.stats[lb.val()]
                i = 0
                m = stat.groups.length

                while i < m
                    groupList.addOption stat.groups[i]
                    i++

            groupsActive = new UiBase("<div></div>")
            groupsActive.delegate "div", "click", ->
                $(this).remove()

            @_content.append "<div>Groups</div>"
            @_content.append groupsActive
            @_content.append "<div>Groups Available</div>"
            groupList = new ListBox(multiple: true)
            @_content.append groupList
            groupList.delegate "option", "click", ->
                # Don't use fat arrow, this refers to obj clicked
                g = $("<div></div>").text($(this).val()).appendTo(groupsActive)
              
                # Stop click from removing the row
                $("<input class=\"regex\" type=\"text\" />").bind("click", ->
                    false
                ).appendTo g

            smootherDiv = $("<div></div>").appendTo(@_content)
            smootherDiv.append "Smooth hours: "
            smoother = $("<input type=\"text\" />").appendTo(smootherDiv)
            expectedDiv = $("<div></div>").appendTo(@_content)
            expectedDiv.append "Expected / grp (eval): "
            expected = $("<input type=\"text\" />").appendTo(expectedDiv)
            ok = new UiBase("<input type=\"button\" value=\"Refresh\" />")
            @_content.append ok

            # Populate "Groups Available" for first
            lb.trigger('change')

            ok.bind 'click', () =>
                stat = @_statsController.stats[lb.val()]
                groups = []
                groupsActive.children().each ->
                    filter = $(".regex", $(self)).val()
                    if filter is ""
                        filter = null
                    else
                        filter = new RegExp(filter)
                    groups.push [$(this).text(), filter]

                smoothOver = @parseInterval(smoother.val())
                expectedVal = eval(expected.val()) or 0
                timeAmt = @parseInterval(timeDivAmt.val(), '12 days')
                timeFrom = new Date().getTime() / 1000 - timeAmt
                options =
                    stat: stat
                    groups: groups
                    smoothOver: smoothOver
                    expectedPerGroup: expectedVal
                    timeFrom: timeFrom
                    autoRefresh: 300

                @_graph.update options

        parseInterval: (interval, def = 0) ->
            if interval == ""
                interval = def

            if /d(y|ay)?s?$/.test(interval)
                #Days
                return parseFloat(interval) * 24 * 60 * 60
            else if /m(in|inute)?s?$/.test(interval)
                #Minutes
                return parseFloat(interval) * 60
            else
                #Hours
                return parseFloat(interval) * 60 * 60


