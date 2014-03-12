
class BaseCollection(object):
    """Base collection for storing lamegame_statview data.
    """
    
    def delete(self, id):
        """Removes the data at key id"""
        raise NotImplementedError()
    
    
    def find(self):
        """Returns an iterator of all documents in self."""
        raise NotImplementedError()


    def findRange(self, a, b):
        """Returns an iterator of all documents between [a, b), exclusive"""
        raise NotImplementedError()


    def get(self, _id, default = None):
        """Returns the document with the given id, or None if there isn't one.
        """
        raise NotImplementedError()
        
    
    def save(self, doc):
        """Saves doc in key doc['_id']"""
        raise NotImplementedError()
    