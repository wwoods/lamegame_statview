define [ 'cs!lib/ui', 'css!eventEditor' ], (ui) ->
    class EventEditor extends ui.Dialog
        constructor: (event, saveCallback) ->
            @controller = ui.fromDom($('.stats-app'))._statsController.events
            @event = event
            @saveCallback = saveCallback
            if not @event.caption?
                @event.caption = "New Event"

            body = new ui.Base('<div class="event-editor"></div>')
            trow = $('<div>').appendTo(body)
            @editCaption = $('<input type="text">')
                    .val(event.caption)
                    .appendTo(trow)

            @editTypes = new ui.ListBox(multiple: true)
                .appendTo(trow)
            for val in @controller.getTypes()
                @editTypes.addOption(val)
            @editTypes.val(event.types)
            @editTypes.multiselect(
                    selectedText: (checked, total) =>
                        vals = @editTypes.val()
                        caption = []
                        for v, i in vals
                            if i >= 3
                                caption.push("...#{ vals.length - i } more")
                                break
                            caption.push(v)

                        return caption.join(", ")
                    noneSelectedText: "user"
                )
                .multiselectfilter()

            @addType = $('<input type="button">')
                    .val("Add filter...")
                    .appendTo(trow)
                    .bind 'click', =>
                        input = $('<input type="text">')
                                .bind 'keydown', (e) =>
                                    if e.which == 13
                                        ok.trigger('click')
                        ok = $('<input type="button" value="ok">')
                        ok.bind 'click', =>
                            newType = input.val()
                            if newType.length > 0
                                if not @controller.addType(newType)
                                    @editTypes.addOption(newType)
                                # Select new option, then refresh
                                curVal = @editTypes.val() or []
                                curVal.push(newType)
                                @editTypes.val(curVal)
                                # Refresh the list of options and select new
                                @editTypes.multiselect("refresh")
                                d.remove()
                        d = new ui.Dialog(body: $('<div>')
                                .append("New event type (will be saved when "
                                    "event is saved)")
                                .append(input)
                                .append(ok))

            @editBody = $('<textarea>')
                    .val(event.content or "")
                    .appendTo(body)

            removeDiv = $('<div>').appendTo(body)
            @shouldDelete = $('<input type="checkbox">delete event</input>')
                    .appendTo(removeDiv)

            confirm = $('<div>').appendTo(body)
            $('<input type="button" value="Save">')
                    .appendTo(confirm)
                    .bind 'click', => @save()
            $('<span>(click outside of dialog to cancel)</span>')
                    .appendTo(confirm)
            @saveStatus = $('<div class="event-editor-error">')
                    .appendTo(body)

            super(body: body)


        save: () ->
            @event.caption = @editCaption.val()
            @event.content = @editBody.val()
            if @event.content.trim().length == 0
                @event.content = null
            @event.types = @editTypes.val() or [ "user" ]

            if @shouldDelete.is(':checked')
                @event.delete = true

            @saveStatus.text('Saving...')

            onError = (e, status, result) =>
                e = result or e
                @saveStatus.text("FAILED: #{ e and e.message or e }")

            targetUrl = @event._id? and 'saveEvent' or 'addEvent'
            originCode = ui.fromDom($('.stats-app')).originCode
            $.ajax
                type: 'POST'
                url: targetUrl
                data: { event: JSON.stringify(@event), origin: originCode }
                error: onError
                success: (result) =>
                    if not result.ok
                        onError(result.error)
                        return

                    @event._id = result.eventId
                    @remove()
                    @saveCallback? and @saveCallback()
