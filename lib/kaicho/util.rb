module Kaicho
  # A utility module for Kaicho.  Don't touch this stuff!
  module Util
    module_function

    # raise an exception if a type is invalid
    #
    # @param [Class] expected the expected type
    # @param [Instance] got the received type
    # @return [True] this method always returns true or raises an exception
    def check_type(expected, got)
      unless expected === got
        raise(TypeError, "expected #{expected.name} got #{got}:#{got.class.name}")
      end

      true
    end
  end
end
