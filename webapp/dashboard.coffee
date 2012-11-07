define [ 'cs!lib/ui.base', 'cs!graph' ], (UiBase, Graph) ->
    class Dashboard extends UiBase
        constructor: () ->
            super('<div class="dashboard"></div>')
            t = $('<table></table>').appendTo(this)
            this.empty()
            r = $('<tr></tr>').appendTo(t)
            s = ' style="position:relative;"'
            w = $(window).width() * 0.5
            c = $('<td' + s + '></td>').appendTo(r)
            c.css('width', w + 'px')
            c.css('height', w * 0.618 + 'px')
            graph = new Graph()
            c.append(graph)
            c = $('<td' + s + '></td>').appendTo(r)
            c.css('width', w + 'px')
            c.css('height', w * 0.618 + 'px')
            graph2 = new Graph()
            c.append(graph2)
            this.append(graph)

