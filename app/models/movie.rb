class Movie < ActiveRecord::Base
    attr_accessible :name, :live, :free, :image, :roku, :ios, :android, :web, :stream_url, :rtmp_url, :release_date, :length, :slug

    validates_presence_of :name, :stream_url, :release_date, :length
    validates_inclusion_of :free, in: [true,false], message: 'must be selected'
    validates_inclusion_of :content_quality, in: ['HD','SD'], message: 'must be selected'
    validates_numericality_of :bitrate

    validates_presence_of :web_url, if: Proc.new{|o| o.use_web_url?}

    mount_uploader :image, MovieImageUploader
    mount_uploader :banner, BannerUploader

    has_many :episodes

    searchkick

    before_validation :slug_change

    def slug_change
        new_name = name.clone

        test_slug = "#{new_name.gsub(' ','-')}"
        other_channels = Channel.where(slug: test_slug)
        if other_channels.any?
            test_slug = "#{new_name.gsub(' ','-')}-#{id.to_s}-movie"
            self.slug = test_slug
        else
            self.slug = test_slug
        end

    end

    def matches?(search_term)
        searchable_string = name.downcase
        if roku == true
            searchable_string += ' roku'
        end
        if ios == true
            searchable_string += ' ios'
        end
        if android == true
            searchable_string += ' android'
        end
        if web == true
            searchable_string += ' web'
        end
        if free == true
            searchable_string += ' free'
        else
            searchable_string += ' premium'
        end
        if searchable_string.include?(search_term.downcase)
            return true
        else
            if searchable_string.include?('roku') && search_term.include?('roku')
                return true
            elsif searchable_string.include?('web') && search_term.include?('web')
                return true
            elsif searchable_string.include?('ios') && search_term.include?('ios')
                return true
            elsif searchable_string.include?('android') && search_term.include?('android')
                return true
            else
                return false
            end
        end
    end

    def available?(device)
        if (device == 'roku' && roku == true) || (device == 'web' && web == true) || (device == 'android' && android == true) || (device == 'ios' && ios == true)
            return true
        else
            return false
        end
    end

    def matches_category?(params)
        matches = true
        if params.has_key?(:genre)
            unless genres.include?(params[:genre])
                matches = false
            end
        end
        if params.has_key?(:content_type)
            # Movies are always video
        end
        if params.has_key?(:content_quality)
            unless params[:content_quality] == content_quality
                matches = false
            end
        end
        if params.has_key?(:free)
            unless params[:free] == free
                matches = false
            end
        end
        return matches
    end

    def watch_url
        return "/watch/movies/#{slug}"
    end

    def device_url
        return "/api/v1/json/movie/#{id.to_s}"
    end

    def auth(token,type)
        if ['Roku','Ipad','Iphone','Ipod','Android'].include? type
            device = Device.where(serial: token, type: type).first

            if device.nil?
                return {success: false, code: 200, message: 'Invalid token'}
            else
                if device.is_active.nil? || device.is_active?
                    if type == 'Roku'
                        unless available?(type.downcase)
                            return {success: false, code: 202, message: 'Not available on this device'}
                        else
                            if free == false
                                if device.premium?
                                    if adult == true && device.adult == true
                                        return {success: true, code: 100, message: 'Success'}
                                    elsif adult == true && (device.adult.nil? || device.adult == false)
                                        return {success: false, code: 205, message: 'Device is not permitted to view Adult Content'}
                                    else
                                        return {success: true, code: 100, message: 'Success'}
                                    end
                                else
                                    return {success: false, code: 206, message: 'Device is not premium'}
                                end
                            else
                                if adult == true && device.adult == true
                                    return {success: true, code: 100, message: 'Success'}
                                elsif adult == true && (device.adult.nil? || device.adult == false)
                                    return {success: false, code: 205, message: 'Device is not permitted to view Adult Content'}
                                else
                                    return {success: true, code: 100, message: 'Success'}
                                end
                            end
                        end
                    else
                        user = User.find(device.user_id)
                        unless available?(type.downcase)
                            return {success: false, code: 202, message: 'Not available on this device'}
                        else
                            if free == false
                                if user.premium?
                                    if adult == true && device.adult == true
                                        return {success: true, code: 100, message: 'Success'}
                                    elsif adult == true && (device.adult.nil? || device.adult == false)
                                        return {success: false, code: 205, message: 'Device is not permitted to view Adult Content'}
                                    else
                                        return {success: true, code: 100, message: 'Success'}
                                    end
                                else
                                    return {success: false, code: 206, message: 'Device is not premium'}
                                end
                            else
                                if adult == true && device.adult == true
                                    return {success: true, code: 100, message: 'Success'}
                                elsif adult == true && (device.adult.nil? || device.adult == false)
                                    return {success: false, code: 205, message: 'Device is not permitted to view Adult Content'}
                                else
                                    return {success: true, code: 100, message: 'Success'}
                                end
                            end
                        end
                    end
                else
                    return {success: false, code: 211, message: 'Device has been suspended'}
                end
            end
        else
            return {success: false, code: 201, message: 'Invalid device type'}
        end
    end

    def roku_url
        return '/api/v1/roku/movie/'+id.to_s+'?serial=SERIAL'
    end

    def feed_type
        return 'Movie'
    end

    def grid_item_ids
        return GridItem.where(video_type: 'Movie', video_id: id).pluck(:grid_id).uniq
    end

    def added_by_admin
        if added_by.present?
            admin = Admin.where(id: added_by).first
            if admin.nil?
                return '[DELETED]'
            else
                return admin.name
            end
        else
            return 'Migration'
        end
    end

    def edited_by_admin
        if edited_by.present?
            admin = Admin.where(id: edited_by).first
            if admin.nil?
                return '[DELETED]'
            else
                return admin.name
            end
        else
            return 'Not Edited'
        end
    end

    def hls_stream
        if use_web_url?
            stream = web_url
        else
            stream = stream_url
        end

        if disable_playlist?
            return "http://#{stream}"
        else
            return "http://#{stream}/playlist.m3u8"
        end
    end

    def rtmp_stream
        if use_web_url?
            stream = web_url
        else
            stream = stream_url
        end
        return "rtmp://#{stream}"
    end
end
