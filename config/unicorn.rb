root = "/var/www/malimar-tv"
working_directory root
pid "#{root}/tmp/pids/unicorn.pid"
stderr_path "#{root}/log/unicorn.log"
stdout_path "#{root}/log/unicorn.log"

listen "/tmp/unicorn.malimar-tv.sock"
worker_processes 5
timeout 150
