class PopulateStreamItemAssociations < ActiveRecord::Migration
  tag :postdeploy

  def self.up
    # the drop migration now exists, so this can no longer run async
    DataFixup::PopulateStreamItemAssociations.run
  end

  def self.down
  end
end
