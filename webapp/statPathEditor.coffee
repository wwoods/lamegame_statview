define ["cs!lib/ui", "cs!statPath", "css!statPathEditor"], (ui, StatPath) ->
    class PathRow extends ui.Base
        constructor: (pathEditor, pathDef) ->
            @pathEditor = pathEditor
            @pathDef = pathDef
            super('<tr class="path-row"></tr>')
            
            # Re-ordering by hand disabled for now, since we'll just sort on
            # path and active status
            # @dragger = $('<div class="dragger"></div>')
            #     .appendTo($('<td></td>').appendTo(@))
            @keeper = $('<input type="checkbox" />')
                .attr('checked', true)
                .appendTo($('<td></td>').appendTo(@))
                .bind("change", () => @update())
            @inactive = $('<input type="checkbox" />')
                .attr('checked', @pathDef.inactive)
                .appendTo($('<td></td>').appendTo(@))
                .bind("change", () => @update())
            @path = new ui.TextBox(expand: true)
                .appendTo($('<td></td>').appendTo(@))
            @path.val(pathDef.path)
            @path.bind("keyup change", () => @_updatePath())
            
            @type = new ui.ListBox().appendTo(@)
            @type.addOption("count", "Counter")
            @type.addOption("count-fuzzy", "Fuzzy Counter")
            @type.addOption("total", "Sample")
            @type.addOption("total-max", "Sampled Max")
            if pathDef.type?
                @type.val(pathDef.type)
            @type.bind("keyup change", () => @update())
            
            @isDirty = false
            @isDeleted = false
            
            
        update: () ->
            # Commit our changes and mark dirty
            newPath = @path.val()
            if @pathDef.path != newPath
                @pathDef.path = newPath
                @isDirty = true
                
            newType = @type.val()
            if @pathDef.type != newType
                @pathDef.type = newType
                @isDirty = true
                
            newDelete = (not @keeper.is(':checked'))
            if newDelete != @isDeleted
                @isDirty = true
                @isDeleted = newDelete
                
            newInactive = @inactive.is(':checked')
            if newInactive != (@pathDef.inactive or false)
                if newInactive
                    @pathDef.inactive = newInactive
                else
                    delete @pathDef.inactive
                @isDirty = true


        _updatePath: () ->
            # Filter the stat path editor's availBlock according to what has
            # been typed.
            pathVal = @path.val()
            if pathVal.lastIndexOf("*") != pathVal.length - 1
                pathVal += "*"
            re = StatPath.prototype.getRegexForPath(pathVal)
            if @_timer?
                clearTimeout(@_timer)
            @_timer = setTimeout(
                () => @pathEditor.flashOptions(re)
                300)

            @update()

            

    class StatPathEditor extends ui.Dialog
        constructor: (options) ->
            @app = options.app
            @controller = options.controller
            @options = options
            
            body = new ui.Base('<div class="stat-path-editor"></div>')
            @pathBlock = new ui.Base('<div class="paths"></div>')
                .appendTo(body)
            @pathTable = new ui.DragContainer
                    root: $('<table></table>')
                    childSelector: 'tr'
                    handleSelector: '.dragger'
                .appendTo(@pathBlock)
            
            @_updateLastSaved()
            
            # Populate @pathTable
            @refresh()
                
            @pathTableAdd = new ui.Base(
                    '<input type="submit" value="Add new" />')
                .bind("click", () =>
                    newDef =
                        id: @_newPathId()
                        path: ''
                    @options.paths.push(newDef)
                    @pathTable.append(new PathRow(@, newDef))
                )
                .appendTo(@pathBlock)
            @pathBlockUndo = new ui.Base(
                    '<input type="submit" value="Undo since save" />')
                .bind("click", () => @undoSinceSave())
                .appendTo(@pathBlock)
            @helpBtn = new ui.Base('<input type="submit" value="Help" />')
                .bind("click", () => @help())
                .appendTo(@pathBlock)
            
            body.append('<div>Unused Paths</div>')
            @availBlock = new ui.ListBox(multiple: true).appendTo(body)
            @availDouble = new ui.ListBox(multiple: true).insertAfter(
                    @availBlock).hide()
            @_availTimer = null
            @_updateAvailable()
            
            super(
                body: body
            )
            
            
        help: () ->
            body = $('<div></div>')
            body.append('<p>Paths are dot-delimited segments of statistics,
                and should use curly braces with a name in the middle to 
                denote groups within those stats.  They may end in or contain
                either a single asterisk to match within a dot-delimiter, or
                a double asterisk to match anything.</p>')
            body.append("<p>Note that curly braces must be used between
                two dots, and nowhere else; e.g. hey.{var}.there is valid,
                but hey.j{var}.there is not.</p>")
            body.append('<p>Examples:</p>')
            ul = $('<ul></ul>').appendTo(body)
            ul.append('<li>hosts.{host}.* - matches hosts.a.b but not 
                hosts.a.b.c</li>')
            ul.append('<li>hosts.{host}.** - matches hosts.a.b and
                hosts.a.b.c</li>')
            new ui.Dialog(body: body).css(maxWidth: '10cm')
            
            
        refresh: () ->
            ### Render @pathTable from @options.paths.  Called on load and 
            after saves to remove deleted rows.
            ###
            @pathTable.empty()
            @pathTable.append('<tr>
                    <td>Keep</td>
                    <td>Inactive</td>
                    <td>Path</td>
                    <td>Type</td>
                </tr>')
            # Sort paths by activity and path
            @options.paths.sort (a,b) ->
                # Sort function; return > 0 for a after b
                ia = if a.inactive then 1 else 0
                ib = if b.inactive then 1 else 0
                if ia != ib
                    return ia - ib
                return a.path.localeCompare(b.path)
            for p in @options.paths
                @pathTable.append(new PathRow(@, p))
            
            
        remove: () ->
            ### Restore the last saved paths, and return
            ###
            # Default to save
            @save () =>
                if @options.onChange
                    @options.onChange()
                super()
            
            
        save: (onOkCallback) ->
            dlg = new ui.Dialog(body: "Saving...")
            
            # Reconstruct @options.paths from dom
            while @options.paths.length > 0
                @options.paths.pop()
                
            saveList = []
            for path in $('tr', @pathTable)
                path = ui.fromDom(path)
                if path instanceof PathRow
                    if not path.isDeleted
                        @options.paths.push(path.pathDef)
                    if path.isDirty
                        saveList.push(path)
            
            onOk = () =>
                dlg.remove()
                @_updateLastSaved()
                @_updateAvailable()
                @refresh()
                if onOkCallback
                    onOkCallback()
                
            onError = (e) =>
                dlg.remove()
                new ui.Dialog(body: "Save failed: " + e)
                
            doNext = () =>
                if saveList.length == 0
                    onOk()
                    return
                    
                next = saveList.pop()
                if next.isDeleted
                    url = 'deletePath'
                    data =
                        pathId: next.pathDef.id
                else
                    url = 'savePath'
                    data =
                        pathDef: JSON.stringify(next.pathDef)
                        
                $.ajax
                    type: 'POST'
                    url: url
                    data: data
                    error: onError
                    success: (result) =>
                        if not result.ok
                            onError(result.error)
                            return
                        next.isDirty = false
                        doNext()
            # Start the chain
            doNext()
            
            
        undoSinceSave: () ->
            while @options.paths.length > 0
                @options.paths.pop()
            for cp in @_copiedPaths
                # Re-copy so that we still have our golden last-saved set
                @options.paths.push($.extend(true, {}, cp))
            @refresh()


        flashOptions: (re) ->
            if @_availTimer?
                clearTimeout(@_availTimer)
            @_availTimer = setTimeout(
                    () =>
                        @availBlock.show()
                        @availDouble.hide()
                    2000)
            @availDouble.reset()
            @availBlock.hide()

            self = this
            @availBlock.children().each () ->
                option = $(this).val()
                if re.test(option)
                    self.availDouble.addOption(option)
                    if self.availDouble.children().length > 4
                        return false
            @availDouble.show()
                        
                        
        _newPathId: () ->
            ### Create a new path ID that doesn't collide with any of 
            @options.paths. 
            ###
            while true
                # Generate a new id of ~ 5 hex chars
                newId = Math.floor(Math.random() * 999999).toString(16)
                isOk = true
                for p in @options.paths
                    if p.id == newId
                        isOk = false
                        break
                if isOk
                    return newId
                    
                    
        _updateAvailable: () ->
            ### Update @availBlock with our un-covered stats
            ###
            @availBlock.empty()
            for p in @controller.availableStats
                if p not of @controller.usedStats and 
                        p not of @controller.inactiveStats
                    @availBlock.addOption(p)
                    
                    
        _updateLastSaved: () ->
            @_copiedPaths = []
            for p in @options.paths
                @_copiedPaths.push($.extend(true, {}, p))
                    
                
                