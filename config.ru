require 'net/http'

map '/' do
  run Rack::Directory.new "public"
end

map '/proxy' do
  run lambda { |env|
    rackreq = Rack::Request.new(env)

    headers = Rack::Utils::HeaderHash.new
    env.each do |key, value|
      if key =~ /HTTP_(.*)/ && key != 'HTTP_CROSSDOMAIN'
        headers[$1] = value
      end
    end

    res = Net::HTTP.start(env['HTTP_CROSSDOMAIN']) do |http|
      m = rackreq.request_method
      case m
      when "GET"
        req = Net::HTTP.const_get(m.capitalize).new(rackreq.fullpath.sub(/\A\/proxy/, ''), headers)
      when "PUT", "POST"
        req = Net::HTTP.const_get(m.capitalize).new(rackreq.fullpath.sub(/\A\/proxy/, ''), headers)
        req.body_stream = rackreq.body
      else
        raise "method not supported: #{m}"
      end

      http.request(req)
    end
 
    [res.code, Rack::Utils::HeaderHash.new(res.to_hash), [res.body]]
  }
end
