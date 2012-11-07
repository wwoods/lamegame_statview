reqs = [ "cs!lib/ui", "cs!statsController", "cs!dashboard" ]
callback = (ui, StatsController, Dashboard) ->
    class StatsApp extends ui.Base
        constructor: () ->
            super('<div class="stats-app"></div>')
            self = @

            @_statsController = new StatsController()

            @text('Loading, please wait')
            $.ajax(
                'getStats'
                {
                    success: (data) ->
                        stats = data.stats
                        window._stats = stats

                        for path in data.paths
                            self._statsController.addStats(path.path, 
                                    path.options)

                        self._statsController.parseStats(stats)
                        console.log(self._statsController)

                        d = new Dashboard()
                        self.empty().append(d)
                }
            )
define(reqs, callback)

