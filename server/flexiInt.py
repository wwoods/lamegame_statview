

class FlexiInt(object):
    """Since Python integers can be of arbitrary size, but mongoDb does not
    support these, FlexiInt helps with the transition.

    The number of length digits starts at 1.  For each _SPLITTER at the
    beginning of the string, length digits is doubled.  The number is then
    length digits of base-16, followed by that number decoded of number digits.
    """

    _BASE_LETTERS = [ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a',
            'b', 'c', 'd', 'e', 'f' ]
    # MUST come after all _BASE_LETTERS for proper sorting.
    _SPLITTER = 'z'

    def __init__(self, v = 0):
        self._value = v
        if isinstance(self._value, basestring):
            self._fromString(self._value)
        elif not isinstance(self._value, (int, long)):
            raise ValueError("Must be integer")
        elif self._value < 0:
            raise ValueError("Negative numbers not supported: {}".format(v))


    def _fromString(self, value):
        """Convert a FlexiInt string from our sortable encoding into self.value.
        """
        # Note - we can actually discard everything that's not the number; the
        # header bytes are all for sortability.
        lengthDigits = 1
        i = 0
        while value[i] == self._SPLITTER:
            lengthDigits *= 2
            i += 1
        i += lengthDigits
        self._value = self._fromBase(value[i:])



    def toString(self):
        """Convert self.value to a sortable string.
        """
        numberString = ""
        base = len(self._BASE_LETTERS)
        numberString = self._toBase(self._value)

        result = []
        overflowLength = base
        lengthDigits = 1
        while overflowLength <= len(numberString):
            overflowLength *= base ** lengthDigits
            lengthDigits *= 2
            result.append(self._SPLITTER)

        result.append(self._toBase(len(numberString), minLength = lengthDigits))
        result.append(numberString)
        return "".join(result)


    @property
    def value(self):
        return self._value


    @classmethod
    def _fromBase(self, v):
        """Convert string v in base len(self._BASE_LETTERS) to python number.
        """
        value = 0
        base = len(self._BASE_LETTERS)
        for d in v:
            value *= base
            value += self._BASE_LETTERS.index(d)
        return value


    @classmethod
    def _toBase(self, v, minLength = 0):
        """Convert number v to base len(self._BASE_LETTERS)"""
        base = len(self._BASE_LETTERS)
        numberString = []
        if v == 0:
            numberString.append(self._BASE_LETTERS[0])
        else:
            while v > 0:
                digit = v % base
                v //= base
                numberString.insert(0, self._BASE_LETTERS[digit])

        digitsLeft = minLength - len(numberString)
        if digitsLeft > 0:
            numberString.insert(0, self._BASE_LETTERS[0] * digitsLeft)

        return "".join(numberString)
