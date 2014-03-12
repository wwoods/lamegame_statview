define [ 'cs!lib/ui', 'css!eventEditor' ], (ui) ->
    class EventEditor extends ui.Dialog
        constructor: (event, saveCallback) ->
            @event = event
            @saveCallback = saveCallback
            if not @event.caption?
                @event.caption = "New Event"

            body = new ui.Base('<div class="event-editor"></div>')
            trow = $('<div>').appendTo(body)
            @editCaption = $('<input type="text">')
                    .val(event.caption)
                    .appendTo(trow)

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

                    @remove()
                    @saveCallback? and @saveCallback()
