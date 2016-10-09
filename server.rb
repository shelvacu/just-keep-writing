require 'em-websocket'
require 'json'

$authors = []
$playing = nil
$text = ""

class Array
  def sample_except(obj)
    self.sample_except_id(self.index(obj))
  end

  def sample_except_id(id)
    return nil if self.length <= 1
    choice = rand(self.length - 1)
    if choice >= id
      choice += 1
    end
    self[choice]
  end
end

class Author
  def self.find(ws)
    $authors.find{|auth|
      auth.ws == ws
    }
  end
  
  def initialize(ws)
    @ws = ws
    @name = nil
    self.touch #heh
  end

  attr_accessor :name
  attr_reader :last_word_time
  attr_reader :ws

  def touch
    @last_word_time = Time.now
  end

  def time_out?
    !@last_word_time.nil? && Time.now - @last_word_time > 10
  end
end

def gen_status
  res = {}
  res["text"] = $text
  if $playing.nil?
    res["playing"] = ""
    res["timeleft"]= 0
  else
    res["playing"]  = $playing.name
    res["timeleft"] = 10 - (Time.now - $playing.last_word_time)
  end
  res
end

def send_status(include_playing = false)
  $authors.each do |auth|
    next if !include_playing and auth == $playing
    auth.ws.send({type: "status", status: gen_status()}.to_json)
  end
end

EM.run {
  EM::WebSocket.run(:host => "0.0.0.0", :port => 8080) do |ws|
    ws.onopen { |handshake|
      puts "WebSocket connection open"

      # Access properties on the EM::WebSocket::Handshake object, e.g.
      # path, query_string, origin, headers

      # Publish message to the client
      ws.send({type: "debug", msg: "Hello Client, you connected to #{handshake.path}"}.to_json)
      $authors << Author.new(ws)
    }

    ws.onclose {
      puts "Connection closed"
      auth = Author.find(ws)
      $authors.delete(auth)
      if $playing == auth
        $playing = $authors.sample
        if not $playing.nil?
          send_status(true) #inform everyone of the new author
        end
      end
    }

    ws.onmessage { |msg|
      puts "Recieved message: #{msg}"
      msg_data = JSON.parse msg #TODO: dont die on invalid non-json data
      auth = Author.find(ws)
      case msg_data["type"]
      when "set_name"
        if $authors.any?{|a| a.name == msg_data["name"]}
          ws.send({type: "set_name_response", result: false}.to_json)
        else
          auth.name = msg_data["name"]
          should_send = false
          if $playing.nil? and
             $authors.find_all{|a| !a.name.nil?}.count >= 2
            $playing = $authors.first
            $playing.touch
            should_send = true
          end
          ws.send({type: "set_name_response", result: true}.to_json)
          send_status(true) if should_send
        end
      when "status" #this should not usually be used, statuses will automaticlally be sent out
        ws.send({type: "status", status: gen_status()}.to_json)
      when "update"
        if $playing != auth
          ws.send({type: "update_response", result: false, why: "not_authoring", status: gen_status()}.to_json)
        else #this person is allowed to append/change things
          case msg_data["change_type"]
          when "backspace"
            next if $text.length < 1
            $text = $text[0..-2] #chop off one character
          when "character"
            case msg_data["character"]
            when /[ -~\n]/ #valid characters
              $text << msg_data["character"]
            else
              ws.send({type: "update_response", result: false, why: "invalid_character"}.to_json)
              next
            end
            auth.touch
            #ws.send {type: "update_response", result: true}
          else
            ws.send({type: "update_response", result: false, why: "invalid_change_type"}.to_json)
            next
          end
          send_status
        end
      else
        ws.send({type: "debug", msg: "unrecognized type #{msg_data["type"]}"}.to_json)
      end
    }
  end

  EM.add_periodic_timer(1) do
    if !$playing.nil? && $playing.time_out?
      new_auth = $authors.sample_except($playing)
      new_auth.touch
      $playing = new_auth
      send_status(true)
    end
  end
}
