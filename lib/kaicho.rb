# frozen_string_literal: true

require 'kaicho/version'
require 'kaicho/util'

# Kaicho is a module for instance variable management.  It can also manage
# class variables, both are referred to as ``resources.''  All class and
# instance variables are automatically considered resources, but only those
# which have been defined with {#def_resource} have the ability to be
# automatically updated.
#
# Auto-updates occur whenever a resource is updated through {#update_resource}
# or if a resource has never been initialized and is accessed through a kaicho
# #{attr_reader}.
#
# Note that all methods act on instances of Classes at the moment.
module Kaicho
  # Called when Kaicho is `include`d
  # if you use the provided class methods, be sure to call super in your
  # initialize method, otherwise they will have no effect
  def self.append_features(rcvr)
    super

    rcvr.instance_variable_set(:@class_resources, [])
    rcvr.instance_variable_set(:@class_triggers, [])

    # @see #def_resource
    rcvr.define_singleton_method(:def_resource) do |*args, &block|
      @class_resources << [args, block]
    end

    # @see #add_triggers
    rcvr.define_singleton_method(:add_triggers) do |*triggers|
      @triggers += triggers
    end
  end

  def initialize
    (self.class.instance_variable_get(:@class_resources))
      .each { |args, block| def_resource(*args, &block) }

    add_triggers(*(self.class.instance_variable_get(:@class_triggers)))

    super
  end

  # adds trigger(s) which can be used to trigger updates of resources
  # who have the trigger set
  #
  # @param [[Symbol]] trigs a list of symbols to be used as triggers
  # @return [True] this method always returns true or raises an exception
  def add_triggers(*trigs)
    @triggers ||= []
    @triggers += trigs.map(&:to_sym)

    true
  end

  # makes both an attr_reader and an attr_writer for the +dname+
  #
  # @param dname the resource to create accessors for
  # @param share the owner of the shared variable
  # @return [True] this method always returns true or raises an exception
  def attr_accessor(dname, share: nil)
    attr_reader(dname, share: share)
    attr_writer(dname, share: share)

    true
  end

  # defines an attr_reader singleton method for a resource which functions just
  # like a typical attr_reader but will update the resource if it hasn't been
  # accessed before.  Unlike an attr_writer, an attr_reader can only be defined
  # for resources that have been previously defined using {#def_resource}.
  #
  # @param dname the resource that will be accessed, as well as the name of the
  #   singleton method.
  #
  # @param share the owner of the shared variable
  # @return [True] this method always returns true or raises an exception
  def attr_reader(dname, share: nil)
    @resources ||= {}

    unless @resources.key?(dname)
      raise(ArgumentError, "resource #{dname} has not been defined")
    end

    read =
      if share.nil?
        -> { instance_variable_get(:"@#{dname}") }
      else
        -> { share.class_variable_get(:"@@#{dname}") }
      end

    define_singleton_method(dname) do
      update_resource(dname, rand) unless resource_defined?(dname)
      read.call
    end

    true
  end

  # defines an attr_writer singleton method for a resource which functions just
  # like a typical attr_writer but will update the resource's dependants when
  # it is called.  Unlike an attr_reader, the resource +dname+ need not be
  # previously defined using {#def_resource}.
  #
  # @param dname the resource that will be accessed.  The name of the singleton
  #   method defined will be +"#{dname}="+.
  # @param share the owner of the shared variable
  # @return [True] this method always returns true or raises an exception
  def attr_writer(dname, share: nil)
    write =
      if share.nil?
        ->(v) { instance_variable_set(:"@#{dname}", v) }
      else
        ->(v) { share.class_variable_set(:"@@#{dname}", v) }
      end

    read =
      if share.nil?
        -> { instance_variable_get(:"@#{dname}") }
      else
        -> { share.class_variable_get(:"@@#{dname}") }
      end

    define_singleton_method(:"#{dname}=") do |v|
      if resource_defined?(dname) && read.call == v
        return v
      end

      write.call(v)
      update_dependants(dname, rand)
      v
    end

    true
  end

  # Define a resource
  #
  # @param [Symbol] dname the name of the resource
  # @param [Hash] depends a hash of dependants with the format
  #   +{ dependant_name: :update_action }+ where update_action is the action
  #   that is taken when this resource is updated.  Update_action can be one of:
  #   - +:update+ - update the dependant before updating this resource
  #   - +:keep+   - keep the dependant if it is already defined, otherwise,
  #     update it
  #   - +:fail+   - don't try to update this resource if the dependant is not
  #     defined
  # @param [Array] triggers a list of triggers.  These triggers must have been
  #   previously defined using {#add_triggers}
  # @param [Boolean] overwrite if a resource with this name already exists,
  #   should it be overwritten
  # @param [Object, nil] share if +nil+, this resource is stored as an instance
  #   variable, else the value must be an instance of a class and this resource
  #   is stored as a class variable owned by the class specified.
  # @param [Symbol] accessor a symbol that determines which attribute accessors
  #   should be generated for this resource
  #   - +:read+,  +:r+  - defines an {#attr_reader}
  #   - +:write+, +:w+  - defines an {#attr_writer}
  #   - +:both+,  +:rw+ - defines both, see {#attr_accessor}
  #   - +:none+         - don't generate any accessors
  # @param [Symbol] accessors alias to accessor
  # @param block a block that will be called, with no arguments, to update this
  #   resource
  # @return [True] this method always returns true or raises an exception
  def def_resource(dname,
                   depends:   {},
                   triggers:  [],
                   overwrite: false,
                   share:     nil,
                   accessor:  :read,
                   accessors: nil,
                   &block)
    @resources ||= {}

    accessor = accessors unless accessors.nil?

    Kaicho::Util.check_type(Symbol, dname)
    Kaicho::Util.check_type(Hash, depends)
    Kaicho::Util.check_type(Array, triggers)

    block = nil unless block_given?

    unless %i[read r write w both rw none].include?(accessor)
      raise(ArgumentError, "invalid accessor: :#{accessor}")
    end

    add_triggers # initialize @triggers to []
    triggers.each do |t|
      raise(ArgumentError, "invalid trigger :#{t}") unless @triggers.include?(t)
    end

    return if @resources.key?(dname) && !overwrite

    @resources[dname] = {
      depends:  depends,
      proc:     block,
      udid:     -1,
      triggers: triggers,
      share:    share,
      varname:  share.nil? ? "@#{dname}" : "@@#{dname}"
    }

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

  # Determine if the value for resource has been defined.  In other words,
  # determine if a resource has ever been updated.
  #
  # If this resource has been defined using {#def_resource} then check if an
  # associated instance or class variable is defined.  Otherwise this method is
  # eqivalent to calling +instance_variable_defined?("@#{dname}")+.
  #
  # @param [Symbol] dname the name of the resource
  # @return [True] this method always returns true or raises an exception
  def resource_defined?(dname)
    return instance_variable_defined?("@#{dname}") unless @resources.key?(dname)

    if @resources[dname][:share].nil?
      instance_variable_defined?(@resources[dname][:varname])
    else
      @resources[dname][:share].class_variable_defined?(
        @resources[dname][:varname]
      )
    end
  end

  # Update a resource
  #
  # This method will update the specified resource and all of its depends
  # and dependants.
  #
  # @see #update_depends
  # @see #update_dependants
  #
  # @param dname the name of the resource
  # @param udid the update-id of this call, this should be left +nil+.  It is
  #   internally to avoid infinite loops during update cascades.
  # @return [True] this method always returns true or raises an exception
  def update_resource(dname, udid = nil)
    unless @resources.key?(dname)
      raise(ArgumentError, "no such resource #{dname}")
    end

    return if @resources[dname][:udid] == udid
    udid ||= rand
    @resources[dname][:udid] = udid

    return unless update_depends(dname, udid)

    unless @resources[dname][:proc].nil?
      result = self.instance_exec(&@resources[dname][:proc])

      if @resources[dname][:share].nil?
        instance_variable_set(@resources[dname][:varname], result)
      else
        @resources[dname][:share].class_variable_set(
          @resources[dname][:varname], result
        )
      end
    end

    update_dependants(dname, udid)

    true
  end

  # Update the prerequisites of a resource.
  #
  # This method will update all resources that +dname+ depends on.
  #
  # @param dname the name of the resource
  # @param udid the update-id of this call, this should be left +nil+.  It is
  #   internally to avoid infinite loops during update cascades.
  # @return [bool] returns false if the resource could not be found, else return true
  def update_depends(dname, udid = nil)
    udid ||= rand
    @resources[dname][:depends].each do |d, o|
      case o
      when :update
        update_resource(d, udid)
      when :keep
        update_resource(d, udid) unless resource_defined?(d)
      when :fail
        return false unless resource_defined?(d)
      when Proc
        update_resource(d, udid) if o.call
      end
    end

    true
  end

  # Update the dependants of +dname+
  #
  # This method will update all resources that have +dname+ in their list of
  # depends.
  #
  # @param dname the name of the resource
  # @param udid the update-id of this call, this should be left +nil+.  It is
  #   internally to avoid infinite loops during update cascades.
  # @return [True] this method always returns true or raises an exception
  def update_dependants(dname, udid = nil)
    udid ||= rand
    @resources.select do |_, v|
      v[:depends].include?(dname) && v[:udid] != udid
    end.each { |d, _| update_resource(d, udid) }

    true
  end

  # Trigger resource updates
  #
  # This method will update all resources that have +trigger+ in their list of
  # triggers.
  #
  # @param [Symbol] trigger the name of the trigger to trigger
  # @return [True] this method always returns true or raises an exception
  def trigger_resources(trigger)
    udid = rand
    res = @resources.select { |_, v| v[:triggers].include?(trigger) }
    res.each { |r, _| update_resource(r, udid) }

    true
  end

  # Update all resources
  #
  # Equivalent to calling {#update_resource} for each resource in +@resources+.
  #
  # @return [True] this method always returns true or raises an exception
  def update_all_resources
    udid = rand

    resource_roots.each { |d| update_resource(d, udid) }

    true
  end

  # Determine the root resources of the current object
  #
  # A resource is a root resource if it either does not depend on anything or
  # all of its dependencies have the +:fail+ action (i.e. they are not managed
  # by kaicho)
  #
  # @return [Array] an array of Symbol where each element is the name of a
  #   resource root
  def resource_roots
    @resources.select do |a, attr|
      attr[:depends].empty? || attr[:depends].all? { |_,a| a == :fail }
    end.map { |a, _| a  }
  end
end
