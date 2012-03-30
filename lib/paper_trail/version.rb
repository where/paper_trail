class Version < ActiveRecord::Base
  belongs_to :item, :polymorphic => true
  validates_presence_of :event
  attr_accessible :item_type, :item_id, :event, :whodunnit, :object, :object_changes

  def self.with_item_keys(item_type, item_id)
    scoped(:conditions => { :item_type => item_type, :item_id => item_id })
  end

  def self.creates
    where :event => 'create'
  end

  def self.updates
    where :event => 'update'
  end

  def self.destroys
    where :event => 'destroy'
  end

  scope :subsequent, lambda { |version|
    where(["#{self.primary_key} > ?", version]).order("#{self.primary_key} ASC")
  }

  scope :preceding, lambda { |version|
    where(["#{self.primary_key} < ?", version]).order("#{self.primary_key} DESC")
  }

  scope :following, lambda { |timestamp|
    # TODO: is this :order necessary, considering its presence on the has_many :versions association?
    where(["#{PaperTrail.timestamp_field} > ?", timestamp]).
      order("#{PaperTrail.timestamp_field} ASC, #{self.primary_key} ASC")
  }

  scope :between, lambda { |start_time, end_time|
    where(["#{PaperTrail.timestamp_field} > ? AND #{PaperTrail.timestamp_field} < ?", start_time, end_time ]).
      order("#{PaperTrail.timestamp_field} ASC, #{self.primary_key} ASC")
  }

  # Restore the item from this version.
  #
  def reify(options = {})
    without_identity_map do
      unless object.nil?
        attrs = YAML::load object

        # Normally a polymorphic belongs_to relationship allows us
        # to get the object we belong to by calling, in this case,
        # +item+.  However this returns nil if +item+ has been
        # destroyed, and we need to be able to retrieve destroyed
        # objects.
        #
        # In this situation we constantize the +item_type+ to get hold of
        # the class...except when the stored object's attributes
        # include a +type+ key.  If this is the case, the object
        # we belong to is using single table inheritance and the
        # +item_type+ will be the base class, not the actual subclass.
        # If +type+ is present but empty, the class is the base class.

        if item
          model = item
        else
          inheritance_column_name = item_type.constantize.inheritance_column
          class_name = attrs[inheritance_column_name].blank? ? item_type : attrs[inheritance_column_name]
          klass = class_name.constantize
          model = klass.new
        end

        attrs.each do |k, v|
          if model.respond_to?("#{k}=")
            model.send :write_attribute, k.to_sym, v
          else
            logger.warn "Attribute #{k} does not exist on #{item_type} (Version id: #{id})."
          end
        end

        model.send "#{model.class.version_association_name}=", self
        model.instance_variable_set(:'@reify_version', self)

        model
      end
    end
  end

  # Returns what changed in this version of the item.  Cf. `ActiveModel::Dirty#changes`.
  # Returns nil if your `versions` table does not have an `object_changes` text column.
  def changeset
    if self.class.column_names.include? 'object_changes'
      if changes = object_changes
        HashWithIndifferentAccess[YAML::load(changes)]
      else
        {}
      end
    end
  end

  # Returns who put the item into the state stored in this version.
  def originator
    previous.try :whodunnit
  end

  # Returns who changed the item from the state it had in this version.
  # This is an alias for `whodunnit`.
  def terminator
    whodunnit
  end

  def sibling_versions
    self.class.with_item_keys(item_type, item_id)
  end

  def next
    sibling_versions.subsequent(self).first
  end

  def previous
    sibling_versions.preceding(self).first
  end

  def index
    id_column = self.class.primary_key.to_sym
    sibling_versions.select(id_column).order("#{id_column} ASC").map(&id_column).index(self.send(id_column))
  end

  private

  # In Rails 3.1+, calling reify on a previous version confuses the
  # IdentityMap, if enabled. This prevents insertion into the map.
  def without_identity_map(&block)
    if defined?(ActiveRecord::IdentityMap) && ActiveRecord::IdentityMap.respond_to?(:without)
      ActiveRecord::IdentityMap.without(&block)
    else
      block.call
    end
  end

end
