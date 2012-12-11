# lamegame_statview

A webservice for displaying stats from graphite or lgTask.

Requires jsProject: https://github.com/sellerengine/jsProject

## Usage

### Requirements

    pip install cherrypy

### Checkout projects

Checkout jsProject and lamegame_statview:

    git clone git://github.com/sellerengine/jsProject.git
    git clone git://github.com/wwoods/lamegame_statview.git

Configure lamegame_statview:

    cd lamegame_statview
    vim app_local.ini

### app_local.ini

    [source]
    type = "graphite"
    url = "http://path/to/graphite/web/interface"
    authKey = "Basic HTTP_AUTH_CODE" (optional)

### Run it!

    python run.py

Point your browser at http://127.0.0.1:8080, and you should see the interface.  Before making graphs you'll need to configure paths - part of the power of using the StatView interface is that it's much more intelligent about your paths than Graphite's built in interface is.  

* Click on the "Add/Edit Stats" button in the upper right corner
* Click "Add new"
* Enter a path matching your statistics... for instance, if your host load data is stored at hosts.myMachine.load, enter: "hosts.{host}.load", and set the type to "Sample".
    * Counter - Aggregation is a counter - that is, each number is an incrementing event, like the number of times a page loads.
    * Sample - Aggregation is a sample - that is, each number from graphite is a sampled value, like machine load.
    * Sampled max - Different stats are aggregated according to the highest
      absolute value within all matching stats, rather than adding.  We use 
      this for "Max age of task on a given host", for instance.  Sample, in
      contrast, would add all of the max ages for each task type, rather than
      returning the overall max.
    * You can use "*" for path wildcards.. if we had other machine stats, using
      hosts.{host}.* would load all available statistics at that level.  "**"
      can be used to match any depth element.
* Click off the dialog to save
* Click the green "Add New..." to add a graph
* Click on a property to add it to the expression... expressions are simple
  math equations.  You can also use min() and max() easily.  See "Expressions"
  below.
* Click on a group name to divide the graphed data according to an element 
  in the path.
* Click off to save, and look at your new graph!  Oo, ahh.  Mouse over for
  tooltips.

That's the gist of it... I'd be inclined to write more docs with more interest.

Thanks for your time!


## Appendix

### Expressions

You can also use "for each {group} add {expression}" for fancy bits.  For 
instance, we have a section that is "Failing expectations."  For this,
we do something like:

    for each user add 100 - actionsCompleted

And smooth that over an hour.  The "for each" clause ensures that the 100 
is applied once per user, and not once to the sum of all actions completed
by all users.


