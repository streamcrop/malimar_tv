class Grid < ActiveRecord::Base
    attr_accessible :name, :grid_id, :image, :sort, :weight, :title_bar, :home_page, :class_type
    searchkick
    mount_uploader :image, MovieImageUploader
    mount_uploader :file, MigrationUploader

    has_many :grid_items

    serialize :items
    serialize :grids

    validates_presence_of :name
    validates_uniqueness_of :name
    validates_presence_of :weight
    validates_numericality_of :weight

    def watch_url
        return '/watch/grid/'+id.to_s
    end

    def feed_type
        return 'Grid'
    end
end
