require 'rubygems'
require 'couchrest'
require 'digest/sha1'
require 'net/http'
require 'uri'
require 'rack'

class Proxy
  
  def initialize
    @couch = CouchRest.database!("http://localhost:5984/cache")
    #@couch.recreate!
  end
  
  def call(env)
    req = Rack::Request.new(env)
    
    if req.path == "/proxy.pac"
      return pac_data env
    end
    
    #puts env.inspect
    
    descriptor = env['REQUEST_URI']
    name = Digest::SHA1.hexdigest(descriptor);
    
    #puts "descriptor is #{descriptor} with hash #{name}"
    
    begin
      doc = @couch.get name
      #puts doc.inspect
      data = @couch.fetch_attachment(doc, "file")
      type = doc['_attachments']['file']['content_type']
      length = doc['_attachments']['file']['content_length']
      puts "Found: type is #{type}: #{descriptor}"
      return [200, {"Content-Type" => type}, data]
    rescue
      puts "Not Found: #{descriptor}"
      
      uri = URI.parse env['REQUEST_URI']
      
      res = Net::HTTP.new(uri.host, uri.port).start do |http|
        http.request_get(uri.path + (!uri.query.nil? ? "?" + uri.query : ""), {"User-Agent" => env['HTTP_USER_AGENT']})
      end
      doc = {"_id"=>name, :saved=>DateTime.now, :uri=>descriptor}
      
      begin
        @couch.save_doc doc
        @couch.put_attachment(doc, "file",res.body, {"Content-Type" => res.content_type})
      end
        
      puts "Done!"
      return [200, {"Content-Type" => res.content_type}, res.body]
    end
    
    return [200, {}, []]
  end
  
  def pac_data(env)
    puts "POSTING CONFIG FILE"
    
    req = Rack::Request.new(env)
    file = <<END
function FindProxyForURL(url, host) {
  if (shExpMatch(host, "*.googleapis.com") || shExpMatch(host, "*.gstatic.com") || shExpMatch(url, "http://maps.google.com/maps/api/js?sensor=false")) {
    return "PROXY #{req.host}:#{req.port}; DIRECT";
  }
  return "DIRECT";
}  
END
    return [200, {"Content-Type" => "application/x-javascript-config"}, file]
  end
  
end
