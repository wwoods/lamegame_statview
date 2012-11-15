define ["cs!lib/ui", "css!statPathEditor"], (ui) ->
    class PathRow extends ui.Base
        constructor: (pathDef) ->
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
            @path.bind("keyup change", () => @update())
            
            @isDirty = false
            @isDeleted = false
            
            
        update: () ->
            # Commit our changes and mark dirty
            newPath = @path.val()
            if @pathDef.path != newPath
                @pathDef.path = newPath
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
            

    class StatPathEditor extends ui.Dialog
        constructor: (options) ->
            @app = options.app
            @controller = options.controller
            @options = options
            
            body = new ui.Base('<div class="stat-path-editor"></div>')
            @pathBlock = new ui.Base('<div class="paths"></div>').appendTo(body)
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
                        isDirty: true
                    @options.paths.push(newDef)
                    @pathTable.append(new PathRow(newDef))
                )
                .appendTo(@pathBlock)
            @pathBlockSave = new ui.Base(
                    '<input type="submit" value="Save" />')
                .bind("click", () => @save())
                .appendTo(@pathBlock)
                
            @availBlock = new ui.ListBox(multiple: true).appendTo(body)
            @_updateAvailable()
            
            super(
                body: body
            )
            
            
        refresh: () ->
            ### Render @pathTable from @options.paths.  Called on load and 
            after saves to remove deleted rows.
            ###
            @pathTable.empty()
            @pathTable.append('<tr>
                    <td>Keep</td>
                    <td>Inactive</td>
                    <td>Path</td>
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
                @pathTable.append(new PathRow(p))
            
            
        remove: () ->
            ### Restore the last saved paths, and return
            ###
            while @options.paths.length > 0
                @options.paths.pop()
            for cp in @_copiedPaths
                @options.paths.push(cp)
            if @options.onChange
                @options.onChange()
            super()
            
            
        save: (pathDef) ->
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
                if @options.onChange
                    @options.onChange()
                @_updateLastSaved()
                @_updateAvailable()
                @refresh()
                
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
                    
                
                