
import cherrypy

Config = cherrypy.lib.reprconf.Config

def mergeConfig(self, *args, **kwargs):
    """Augment cherrypy.lib.reprconf.Config with a method that merges top-level
    dicts into each other, so that app_local.ini can specify a minor subset
    of options and still get defaults from app.ini.
    """
    other = cherrypy.lib.reprconf.Config(*args, **kwargs)
    # Top-level keys are namespaces to merge, second level should get replaced
    for k, v in other.items():
        mergeFrom = self.get(k, {})
        mergeFrom.update(v)
        self[k] = mergeFrom
cherrypy.lib.reprconf.Config.merge = mergeConfig
