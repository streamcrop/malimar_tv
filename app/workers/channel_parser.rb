class ChannelParser
    @queue = :channel_parser
    def self.perform(item, grid_id)
        migration_item = VodMigrationItem.create(status: 'In Progress',completed: false, migration_id: grid_id)
        begin
            grid = Grid.find(grid_id)
            channel = Channel.new
            channel.grid_id = grid_id
            channel.name = item['title']
            channel.free = grid.free
            channel.synopsis = item['synopsis']
            new_name = channel.name.clone

            test_slug = "#{new_name.gsub(' ','-')}"
            other_channels = Channel.where(slug: test_slug)
            if other_channels.any?
                test_slug = "#{new_name.gsub(' ','-')}-#{grid_id.to_s}-channel"
                channel.slug = test_slug
            else
                channel.slug = test_slug
            end

            channel.adult = grid.adult
            channel.content_type = item['contentType']

            #get stream name
            if item.has_key?('media')
                media = item['media'].to_hash

                channel.content_quality = media['streamQuality']
                channel.stream_url = media['streamUrl']
                channel.bitrate = media['streamBitrate']
                url = media['streamUrl'].to_s.clone
                url = url.gsub!('/playlist.m3u8','')
                url = url.split('')
                url.reverse!
                name_array = Array.new
                url.each do |i|
                    if i == '/'
                        break
                    else
                        name_array.push(i)
                    end
                end
                name_array.reverse!
                url = channel.stream_url
                channel.stream_name = name_array.join('')
                if url.start_with?('http://')
                    url.gsub!('http://','')
                end
                if url.start_with?('rtmp://')
                    url.gsub!('rtmp://','')
                end
                if url.end_with?('/playlist.m3u8')
                    url.gsub!('/playlist.m3u8','')
                end

                channel.stream_url = url
            end

            channel.genres = ""

            if item.has_key?('genres')
                unless item['genres']['genre'].blank?
                    item['genres']['genre'].each do |genre|
                        unless genre.nil?
                            channel.genres += "#{genre}\r\n"
                        end
                    end
                end
            end

            channel.actors = ""

            if item.has_key?('actors')
                unless item['actors']['actor'].blank?
                    item['actors']['actor'].each do |actor|
                        unless actor.nil?
                            channel.actors += "#{actor}\r\n"
                        end
                    end
                end
            end

            channel.roku = true
            channel.web = true
            channel.ios = true
            channel.android = true

            channel.remote_image_url = item['hdImg']

            if Channel.where(stream_url: channel.stream_url).count < 1
                if channel.save
                    GridItem.create(grid_id: grid_id, video_id: channel.id, video_type: 'Channel')
                    migration_item.destroy
                else
                    migration_item.status = 'Error'
                    migration_item.completed = true
                    migration_item.error = 'Channel could not be saved: '+item.inspect
                    migration_item.save
                end
            else
                migration_item.status = 'Error'
                migration_item.completed = true
                migration_item.error = 'Channel could not be saved: Duplicate Entry (' + item['title'] + ')'
                migration_item.save
            end
        rescue => e
            migration_item.status = 'Error'
            migration_item.completed = true
            migration_item.error = 'Exception raised (Channel): '+ e.message + ' | ' + e.backtrace[0]
            migration_item.save
        end
    end
end
