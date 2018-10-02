require "kaicho/version"

# Kaicho is a module that assists in a class's resource management.
# It enables you to chain resources together.  Each resource when changed
# will update all of its dependants.  Additionally, if you try to access a
# resource which has not been initialized, it will update itself along with
# all resources it depends on.
#
# This is useful if you have a class with many instance variables that all
# form a dependancy tree.  For instance:
#
# ```
# class Fruits
#   include Kaicho
#
#   def intialize
#     def_resource :apples, accessor: :both { @apples || 0 }
#     def_resource :oranges, accessor: :both { @oranges || 0 }
#     def_resource :total, depend: { apples: :fail, oranges: :fail } do
#       puts "computing total"
#       @apples + @oranges
#     end
#   end
# end
#
# f = Fruits.new
# f.apples         #=> 0
# f.apples += 1    #=> 1
# computing total
# f.oranges = 10   #=> 10
# computing total
# f.total          #=> 11
# f.oranges = 2
# computing total
# f.total          #=> 13
# f.total          #=> 13
# ```
module Kaicho
  # adds trigger(s) which can be used to trigger updates of resources
  # who have the trigger set
  #
  # @param t a list of symbols to be used as triggers
  def add_triggers(*t)
    @triggers ||= []
    @triggers += t.map(&:to_sym)
  end

  # makes both an attr_reader and an attr_writer for the `dname`
  #
  # @param dname the resource to create accessors for
  # @param share the owner of the shared variable
  def attr_accessor(dname, share: nil)
    attr_reader(dname, share: nil)
    attr_writer(dname, share: nil)
  end

  # builds an attr_reader for a resource which functions just like a typical
  # attr_reader but will update the resource if it hasn't been accessed
  # before.
  #
  # @param dname the resource that will be accessed
  # @param share the owner of the shared variable
  def attr_reader(dname, share: nil)
    read = share.nil? ? -> { instance_variable_get(:"@#{dname}") }
                      : -> { share.class_variable_get(:"@@#{dname}") }
    define_singleton_method(dname) do
      update_resource(dname) unless @resources[dname][:udid].positive?
      read.call
    end
  end

  # builds an attr_writer for a resource which functions just like a typical
  # attr_writer but will update the resource's dependants when it is called.
  #
  # @param dname the resource that will be accessed
  # @param share the owner of the shared variable
  def attr_writer(dname, share: nil)
    write = share.nil? ? -> (v) { instance_variable_set(:"@#{dname}", v) }
                       : -> (v) { share.class_variable_set(:"@@#{dname}", v) }
    define_singleton_method(:"#{dname}=") do |v|
      write.call(v)
      update_dependants(dname)
      v
    end
  end

  def check_type(expected, got)
    unless expected === got
      raise TypeError.new("expected #{expected.name} got #{got}:#{got.class.name}")
    end
  end

  # define a resource
  #
  # @param dname the name of the resource
  # @param depends a hash of dependants with the format
  #                { dependant_name: :update_action }
  #                where update_action is the action that
  #                is taken when this resource is updated.
  #                update_action can be one of
  #                - :update - update the dependant before updating this resource
  #                - :keep   - keep the dependant if it is already defined,
  #                            otherwise, update it
  #                - :fail   - don't try to update this resource if the
  #                            dependant is not defined
  #
  #                -
  def def_resource(dname,
                   depends:   {},
                   triggers:  [],
                   overwrite: false,
                   share:    nil,
                   accessor: :read,
                   &block)
    @resources ||= {}

    check_type(Symbol, dname)
    check_type(Hash, depends)
    check_type(Array, triggers)

    return if @resources.key?(dname) && !overwrite

    add_triggers # initialize @triggers to []
    triggers.each do |t|
      raise ArgumentError.new("invalid trigger ':#{t}'") unless @triggers.include?(t)
    end

    depends.map =
      case depends
      when Array
        depends.map { |d| [d, :keep] }.to_h
      when Hash
        depends
      else
        { depends => :keep }
      end

    @resources.merge!(
      dname => {
        depends:  depends,
        proc:     block,
        udid:     -1,
        triggers: triggers & (@triggers || []),
        share:    share,
        varname:  share.nil? ? "@#{dname}" : "@@#{dname}"
      }
    )

    case accessor
    when :read,  :r
      attr_reader(dname, share: share)
    when :write, :w
      attr_writer(dname, share: share)
    when :both,  :rw
      attr_accessor(dname, share: share)
    end
  end

  def resource_defined?(dname)
    return instance_variable_defined?("@#{dname}") unless @resources.key?(dname)

    if @resources[dname][:share].nil?
      instance_variable_defined?(@resources[dname][:varname])
    else
      @resources[dname][:share].class_variable_defined?(@resources[dname][:varname])
    end
  end

  def update_resource(dname, udid=nil)
    raise "no such resource #{dname}" unless @resources.key?(dname)

    return if @resources[dname][:udid] == udid

    udid ||= rand

    return unless update_requisites(dname, udid)

    result = @resources[dname][:proc].call

    if @resources[dname][:share].nil?
      instance_variable_set(@resources[dname][:varname], result)
    else
      @resources[dname][:share].class_variable_set(@resources[dname][:varname], result)
    end

    @resources[dname][:udid] = udid

    update_dependants(dname, udid)
  end

  def update_requisites(dname, udid=nil)
    udid ||= rand
    @resources[dname][:depends].each do |d, o|
      case o
      when :update
        update_resource(d, udid)
      when :keep
        update_resource(d, udid) unless resource_defined?(d)
      when :fail
        unless resource_defined?(d)
          return false
        end
      else
        raise "option #{o} not understood for #{d} while updating #{dname}"
      end
      true
    end
  end

  def update_dependants(dname, udid=nil)
    udid ||= rand
    dependants = @resources.select { |_,v| v[:depends].include?(dname) && v[:udid] != udid }
    dependants.each { |d,_| update_resource(d, udid) }
  end

  def trigger_resources(trigger)
    udid = rand
    res = @resources.select { |_,v| v[:triggers].include?(trigger) }
    res.each { |r,_| update_resource(r, udid) }
  end

  def update_all_resources
    udid = rand
    @resources.keys.each { |d| update_resource(d, udid) }
  end
end
