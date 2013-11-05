define ["cs!lib/ui", "css!aliasEditor"], (ui) ->
    class AliasEditor extends ui.Dialog
        constructor: (options) ->
            @app = options.app
            @controller = options.controller
            @options = options

            body = new ui.Base('<div class="alias-editor"></div>')

            @dbAliases = {}
            for a of @controller.groups
                @dbAliases[a] = {}
            for a in @options.aliases
                @dbAliases[a.id] = a.aliases

            @table = $('<table></table>').appendTo(body)
            for group of @dbAliases
                @table.append(new GroupAliasRow(@, group, @dbAliases[group]))

            super(body: body)


        remove: () ->
            @save () =>
                if @options.onChange
                    @options.onChange()
                super()


        save: (onOkCallback) ->
            saveList = []
            for r in @table.children().children()
                e = ui.fromDom(r)
                if e not instanceof GroupAliasRow
                    continue

                def = { id: e.group, aliases: e.getAliases() }
                if @_isChanged(def)
                    saveList.push(def)

            dlg = new ui.Dialog(body: "Saving...")

            onOk = () =>
                dlg.remove()
                if onOkCallback
                    # Feed from @dbAliases back to @options.aliases
                    while @options.aliases.length > 0
                        @options.aliases.pop()
                    for group of @dbAliases
                        @options.aliases.push(
                            id: group, aliases: @dbAliases[group])
                    onOkCallback()

            onError = (e) =>
                dlg.remove()
                new ui.Dialog(body: "Save failed: #{ e }")

            doNext = () =>
                next = saveList.pop()
                if not next?
                    onOk()
                    return

                $.ajax
                    type: 'POST'
                    url: 'saveAlias'
                    data: { groupDef: JSON.stringify(next) }
                    error: onError
                    success: (result) =>
                        if not result.ok
                            onError(result.error)
                            return

                        @dbAliases[next.id] = next.aliases

                        doNext()

            doNext()


        _isChanged: (def) ->
            a = @dbAliases[def.id]
            b = def.aliases
            for n of a
                if n not of b
                    return true
            for n of b
                if n not of a
                    return true
            for n of a
                if a[n] != b[n]
                    return true
            return false



    class GroupAliasRow extends ui.Base
        constructor: (@editor, @group, @aliases) ->
            super('<tr></tr>')

            $('<td></td>').text(@group).appendTo(@)
            @aliasTable = $('<table></table>')
            $('<td></td>').append(@aliasTable).appendTo(@)

            possibleValues = (request, response) =>
                vals = @editor.controller.groups[@group]
                used = @getAliases()
                realVals = []
                for v in vals
                    if v not of used or v == request.term
                        realVals.push(v)
                response($.ui.autocomplete.filter(realVals, request.term))

            for aliased of @aliases
                @aliasTable.append(new AliasRow(possibleValues, aliased,
                        @aliases[aliased]))

            @adder = $('<tr><td><input type="submit" value="add..."/>'
                    + '</td></tr>')
                    .appendTo(@aliasTable)
                    .bind("click", () =>
                        @adder.before(new AliasRow(possibleValues))
                    )


        getAliases: () ->
            # Returns database-ready aliases
            result = {}
            for aliasElement in @aliasTable.children().children()
                row = ui.fromDom(aliasElement)
                if row not instanceof AliasRow
                    continue
                result[row.fromValBox.val()] = row.toValBox.val()
            return result


    class AliasRow extends ui.Base
        constructor: (possibleValues, from, to) ->
            super('<tr></tr>')
            @fromValBox = $('<input type="text"/>')
            completeClosing = false
            @fromValBox.val(from)
                    .autocomplete(
                        source: possibleValues
                        minLength: 0
                        close: () ->
                            completeClosing = true
                            setTimeout (() -> completeClosing = false), 100
                    ).focus(() ->
                        if !completeClosing
                            $(this).autocomplete('search')
                    )
            @fromValBox.autocomplete("widget").css(
                    'max-height': '300px'
                    'overflow-y': 'auto')
            @toValBox = $('<input type="text"/>')
            @toValBox.val(to)
            $('<td></td>')
                    .append(@fromValBox)
                    .appendTo(@)
            $('<td></td>')
                    .append(@toValBox)
                    .appendTo(@)
            $('<td><input type="submit" value="Remove"/></td>')
                    .bind("click", () => @remove())
                    .appendTo(@)


    return AliasEditor
