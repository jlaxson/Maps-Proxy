require "proxy"

proxy = Proxy.new

app = proc do |env|
  proxy.call env
end

run app