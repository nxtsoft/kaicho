# Kaicho
[![Build Status](https://travis-ci.org/annacrombie/kaicho.svg?branch=master)](https://travis-ci.org/annacrombie/kaicho)
[![Coverage Status](https://coveralls.io/repos/github/annacrombie/kaicho/badge.svg?branch=master)](https://coveralls.io/github/annacrombie/kaicho?branch=master)
[![Inline docs](http://inch-ci.org/github/annacrombie/kaicho.svg?branch=master&style=shields)](http://inch-ci.org/github/annacrombie/kaicho)
[![Gem Version](https://badge.fury.io/rb/kaicho.svg)](https://badge.fury.io/rb/kaicho)

Kaicho is the boss for your resources.  It handles keeping everything up to
date.

```ruby
class Fruits
  include Kaicho

  def intialize
    def_resource :apples, accessor: :both { @apples || 0 }
    def_resource :oranges, accessor: :both { @oranges || 0 }
    def_resource :total, depend: { apples: :fail, oranges: :fail } do
      puts "computing total"
      @apples + @oranges
    end
  end
end

f = Fruits.new
f.apples         #=> 0
f.apples += 1    #=> 1
computing total
f.oranges = 10   #=> 10
computing total
f.total          #=> 11
f.oranges = 2
computing total
f.total          #=> 13
f.total          #=> 13
```
