
import shelve

from server.storage.base import BaseCollection

class ShelveCollection(BaseCollection):
    def __init__(self, url):
        """url like shelve://(filepath relative or absolute"""
        fname = url[len('shelve://'):]
        self._shelf = shelve.open(fname)
        
        
    def delete(self, id):
        key = self._getKey(id)
        del self._shelf[key]
        self._shelf.sync()
        
        
    def find(self):
        return self._shelf.itervalues()


    def findRange(self, a, b):
        """Returns an iterator of all documents between [a, b), exclusive"""
        for k, v in self._shelf.iteritems():
            if a <= k < b:
                yield v
    
    
    def save(self, doc):
        key = self._getKey(doc['_id'])
        self._shelf[key] = doc
        self._shelf.sync()
        
        
    def _getKey(self, id):
        if isinstance(id, unicode):
            id = id.encode('utf-8')
        return id
