require 'kaicho/version'
require 'kaicho/util'

# Kaicho is a module for instance variable management.  It can also manage class
# variables, both are referred to as ``resources.''  All class and instance
# variables are automatically considered resources, but only those which have
# been defined with {#def_resource} have the ability to be automatically
# updated.
#
# Auto-updates occur whenever a resource is updated through {#update_resource}
# or if a resource has never been initialized and is accessed through a kaicho
# #{attr_reader}.
#
# Note that all methods act on instances of Classes at the moment.
module Kaicho
  # adds trigger(s) which can be used to trigger updates of resources
  # who have the trigger set
  #
  # @param [[Symbol]] t a list of symbols to be used as triggers
  # @return [True] this method always returns true or raises an exception
  def add_triggers(*t)
    @triggers ||= []
    @triggers += t.map(&:to_sym)

    true
  end

  # makes both an attr_reader and an attr_writer for the +dname+
  #
  # @param dname the resource to create accessors for
  # @param share the owner of the shared variable
  # @return [True] this method always returns true or raises an exception
  def attr_accessor(dname, share: nil)
    attr_reader(dname, share: nil)
    attr_writer(dname, share: nil)

    true
  end

  # builds an attr_reader for a resource which functions just like a typical
  # attr_reader but will update the resource if it hasn't been accessed
  # before.
  #
  # @param dname the resource that will be accessed
  # @param share the owner of the shared variable
  # @return [True] this method always returns true or raises an exception
  def attr_reader(dname, share: nil)
    @resources ||= {}
    raise ArgumentError.new("resource #{dname} has not been defined") unless @resource.key?(dname)

    read = share.nil? ? -> { instance_variable_get(:"@#{dname}") }
                      : -> { share.class_variable_get(:"@@#{dname}") }
    define_singleton_method(dname) do
      update_resource(dname) unless @resources[dname][:udid].positive?
      read.call
    end

    true
  end

  # builds an attr_writer for a resource which functions just like a typical
  # attr_writer but will update the resource's dependants when it is called.
  #
  # @param dname the resource that will be accessed
  # @param share the owner of the shared variable
  # @return [True] this method always returns true or raises an exception
  def attr_writer(dname, share: nil)
    @resources ||= {}
    raise ArgumentError.new("resource #{dname} has not been defined") unless @resource.key?(dname)

    write = share.nil? ? -> (v) { instance_variable_set(:"@#{dname}", v) }
                       : -> (v) { share.class_variable_set(:"@@#{dname}", v) }
    define_singleton_method(:"#{dname}=") do |v|
      write.call(v)
      update_dependants(dname)
      v
    end

    true
  end

  # Define a resource
  #
  # @param [Symbol] dname the name of the resource
  # @param [Hash] depends a hash of dependants with the format
  #   +{ dependant_name: :update_action }+ where update_action is the action that
  #   is taken when this resource is updated.  Update_action can be one of:
  #   - +:update+ - update the dependant before updating this resource
  #   - +:keep+   - keep the dependant if it is already defined, otherwise, update it
  #   - +:fail+   - don't try to update this resource if the dependant is not defined
  # @param [Array] triggers a list of triggers.  These triggers must have been
  #   previously defined using @see #add_triggers
  # @param [Boolean] overwrite if a resource with this name already exists, should it be overwritten
  # @param [Object, nil] share if +nil+, this resource is stored as an instance variable, else
  #   the value must be an instance of a class and this resource is stored as a
  #   class variable owned by the class specified.
  # @param [Symbol] accessor a symbol that determines which attribute accessors should be
  #   generated for this resource
  #   - +:read+,  +:r+  - @see #attr_reader
  #   - +:write+, +:w+  - @see #attr_writer
  #   - +:both+,  +:rw+ - @see #attr_accessor
  #   - +:none+         - don't generate any accessors
  # @param block a block that will be called, with no arguments, to update this resource
  # @return [True] this method always returns true or raises an exception
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

    true
  end

  # Determine if a resource has been defined
  #
  # @param [Symbol] dname
  # @return [True] this method always returns true or raises an exception
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
