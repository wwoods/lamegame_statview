define(
    [
        "d3.v2.min", "css!lib/reset", "css!main", "cs!lib/ui"
        "cs!jQueryExtensions"
        "cs!statsApp"
    ]
    () ->
        $ () ->
            StatsApp = require("cs!statsApp")
            $('body').empty().append(new StatsApp())
)

