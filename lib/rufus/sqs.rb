#
#--
# Copyright (c) 2007-2008, John Mettraux, jmettraux@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#++
#

#
# Made in Japan, by:
#
#   John dot Mettraux at OpenWFE dot org
#
# and Modified by a Japanese in Canada:
#
#   Koichi Hirano, internalist aaaat gmail doooot com
#

require 'base64'
require 'cgi'
require 'net/https'
require 'rexml/document'
require 'time'
require 'pp'

require 'rubygems'
require 'rufus/verbs'


module Rufus
module SQS

    #
    # An SQS message (after its creation).
    #
    class Message

        attr_reader :queue, :message_body, :receipt_handle

        def initialize (queue, xml_element)

            @queue = queue
            @receipt_handle = SQS::get_element_text(xml_element, "ReceiptHandle")
            @message_body = SQS::get_element_text(xml_element, "Body")
        end

        #
        # Connects to the queue service and deletes this message in its queue.
        #
        def delete

            @queue.queue_service.delete_message(@queue, @receipt_handle)
            
        end
    end

    #
    # An SQS queue (gathering all the necessary info about it 
    # in a single class).
    #
    class Queue

        attr_reader :queue_service, :host, :path, :name
        attr_accessor :approximate_number_of_messages, :visibility_timeout

        def initialize (queue_service, xml_element)

            @queue_service = queue_service

            s = xml_element.text.to_s

            m = Regexp.compile('^http://(.*)(/.*)').match(s)
            @host = m[1]
            @name = m[2][1..-1]
            @path = m[2]
            
            @approximate_number_of_messages = nil
            @visibility_timeout = nil
        end
    end

    #
    # As the name implies.
    #
    class QueueService

        AWS_VERSION = "2008-01-01"
        DEFAULT_QUEUE_HOST = "queue.amazonaws.com"

        def initialize (queue_host=nil)

            @queue_host = queue_host || DEFAULT_QUEUE_HOST
        end

        #
        # Lists the queues for the active AWS account.
        # If 'prefix' is given, only queues whose name begin with that
        # prefix will be returned.
        #
        def list_queues (prefix=nil)

            queues = []
            
            request_params = {}
            
            request_params["Action"] = "ListQueues"
            request_params["QueueNamePrefix"] = prefix if prefix

            doc = do_action :get, @queue_host, "", request_params
            doc.elements.each("//QueueUrl") do |e|
                queues << get_queue_attributes(Queue.new(self, e))
            end
            return queues
        end

        #
        # Creates a queue.
        #
        # If the queue name doesn't comply with SQS requirements for it,
        # an error will be raised.
        #
        def create_queue (queue_name, visibility_timeout = 30)
          
            params = {}
            params["Action"] = "CreateQueue"
            params["QueueName"] = queue_name
            params["DefaultVisibilityTimeout"] = visibility_timeout


            doc = do_action :post, @queue_host, "/", params

            doc.elements.each("//QueueUrl") do |e|
                return e.text.to_s
            end
        end

        #
        # Given some content ('text/plain' content), send it as a message to
        # a queue.
        # Returns true if successful.
        #
        # The queue might be a queue name (String) or a Queue instance.
        #
        def send_message (queue, content)

            queue = resolve_queue(queue)

            params = {}
            params["Action"] = "SendMessage"
            params["MessageBody"] = content
            params["QueueName"] = queue.name
            
            doc = do_action :get, queue.host, "/#{queue.name}", params

            SQS::get_element_text(doc, '//MessageId') # This is to verify if MessageId exists in the response. 
            
            return true # Not return MessageId anymore as MessageId is not reusable anywhere else in SQS API 2008-01-01
        end

        alias :put_message :send_message
        alias :post_message :send_message

        #
        # Retrieves a bunch of messages from a queue. Returns a list of
        # Message instances.
        #
        # There are actually two optional params that this method understands :
        #
        # - :VisibilityTimeout  the duration in seconds of the message visibility in the
        #             queue
        # - :MaxNumberOfMessages    the max number of message to be returned by this call, upto 10
        #
        # The queue might be a queue name (String) or a Queue instance.
        #
        def get_messages (queue, params={})

            queue = resolve_queue(queue)

            params["Action"] = "ReceiveMessage"

            doc = do_action :get, queue.host, "/#{queue.name}", params

            messages = []

            doc.elements.each("//Message") do |me|
                messages << Message.new(queue, me)
            end

            messages
        end


        #
        # Deletes a given message.
        #
        # The queue might be a queue name (String) or a Queue instance.
        # The receipt_handle of a message can be found in a returned message of get_messages call.        
        # If fails, e.g. authentication error, will raise an exception due to 403
        #
        def delete_message (queue, receipt_handle)

            queue = resolve_queue(queue)

            params = {}            
            params["Action"] = "DeleteMessage"
            params["ReceiptHandle"] =  receipt_handle

            doc = do_action :get, queue.host, "/#{queue.name}", params

        end

        #
        # flush_queue is not a native action and there is no gurantee that this kind of method 
        # can actually delete all the message due to the visibility timeout.
        # now flushe_queue does nothing
        #
        def flush_queue (queue)
          
          pp "Obsolete Action - nothing done"
          
        end

        #
        # Deletes the queue. Returns true if the delete was successful.
        # This call will delete the queue even if there remain some messages in the queue.
        # So, be careful.
        #
        def delete_queue (queue)

            queue = resolve_queue(queue)
            
            params = {}            
            params["Action"] = "DeleteQueue"

            doc = do_action :get, @queue_host, "/#{queue.name}", params

        end

        #
        # Given a queue name, a Queue instance is returned.
        #
        def get_queue (queue_name)

            l = list_queues(queue_name)

            l.each do |q|
                if q.name == queue_name
                  get_queue_attributes(q)
                  return q 
                end
            end

            raise "found no queue named '#{queue_name}'"
        end
        
        #
        # Gets attributes of a queue, and returns a Queue instance with updated attribute values.
        #
        # Attributes to be obtained are:
        #   VisibilityTimeout - The length of time (in seconds) that a message that has been 
        #                       received from a queue will be invisible to other receiving 
        #                       components when they ask to receive messages. During the visibility 
        #                       timeout, the component that received the message usually processes 
        #                       the message and then deletes it from the queue.
        #   ApproximateNumberOfMessages - the approximate number of messages in the queue
        #
        def get_queue_attributes(queue)
          
          queue = resolve_queue(queue)
          
          params = {}
          params["Action"] = "GetQueueAttributes"
          params["AttributeName"] = "All"

          doc = do_action :get, @queue_host, "/#{queue.name}", params

          doc.elements.each("//Attribute") do |me|
            case me.elements["Name"].text
            when "VisibilityTimeout"
              queue.visibility_timeout = me.elements["Value"].text.to_i
            when "ApproximateNumberOfMessages"
              queue.approximate_number_of_messages =  me.elements["Value"].text.to_i
            else
              #nothing
            end
          end

          return queue
        end

        #
        # Sets attributes of a queue, and returns a Queue instance with updated attribute values.
        #
        # Only attribute to be updated today is:
        #   VisibilityTimeout - The length of time (in seconds) that a message that has been 
        #                       received from a queue will be invisible to other receiving 
        #                       components when they ask to receive messages. During the visibility 
        #                       timeout, the component that received the message usually processes 
        #                       the message and then deletes it from the queue.
        #
        def set_queue_attributes(queue, param)

          queue = resolve_queue(queue)
          params = {}
          params["VisibilityTimeout"] = param["VisibilityTimeout"]
          params["Action"] = "SetQueueAttributes"

          doc = do_action :get, @queue_host, "/#{queue.name}", params

          return get_queue_attributes(queue)
        end

        protected

            #
            # 'queue' might be a Queue instance or a queue name. 
            # If it's a Queue instance, it is immediately returned,
            # else the Queue instance is looked up and returned.
            #
            def resolve_queue (queue)

                return queue if queue.kind_of?(Queue)
                get_queue queue.to_s
            end

            def do_action (action, host, path, params, content=nil)

                date = Time.now.httpdate

                raise "No $AMAZON_ACCESS_KEY_ID env variable found" unless ENV['AMAZON_ACCESS_KEY_ID']
                params["AWSAccessKeyId"] = ENV['AMAZON_ACCESS_KEY_ID']
                params["SignatureVersion"] = 1                
                params["Timestamp"] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.000Z')
                params["Version"] = AWS_VERSION

                path += "?" + params.sort_by {|v| v[0].downcase }.collect{|p| p[0].to_s + "=" + URI.encode(p[1].to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))}.join("&")
                str_to_sign = params.sort_by {|v| v[0].downcase }.collect{|p| p[0].to_s + p[1].to_s}.join("")
                path += "&Signature=#{hmac_sha1_signature(str_to_sign)}"
                h = {}

                h['Content-type'] = 'text/plain'
                h['Content-length'] = content.length.to_s if content

                res = Rufus::Verbs::EndPoint.request(
                    action, 
                    :host => host,
                    :path => path, 
                    :d => content,
                    :headers => h)

                case res
                when Net::HTTPSuccess, Net::HTTPRedirection, Net::HTTPClientError
                    doc = REXML::Document.new(res.read_body)
                    raise_errors(doc)
                else
                    doc = res.error!
                end

                doc
            end

            #
            # Scans the SQS XML reply for potential errors and raises an
            # error if he encounters one.
            #
            def raise_errors (doc)

                doc.elements.each("//Error") do |e|

                    code = SQS.get_element_text(e, "Code")
                    return unless code

                    message = SQS.get_element_text(e, "Message")
                    raise "Rufus::SQS::#{code} : #{message}"
                end
            end

            #
            # Generate hmac sha1 signature of a given string.
            # SQS version 2008-01-01 requires a signature of request parameter sets sorted 
            # by parameters for authentication.
            #
            def hmac_sha1_signature(string)

              digest = OpenSSL::Digest::Digest.new 'sha1'

              key = ENV['AMAZON_SECRET_ACCESS_KEY']

              raise "No $AMAZON_SECRET_ACCESS_KEY env variable found" unless key
              
              sig = OpenSSL::HMAC.digest(digest, key, string)
              sig = Base64.encode64(sig).strip
              sig = URI.encode(sig, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
            end 

    end

    #
    # A convenience method for returning the text of a sub element,
    # maybe there is something better in REXML, but I haven't found out
    # yet.
    #
    def SQS.get_element_text (parent_elt, elt_name)

        e = parent_elt.elements[elt_name]
        return nil unless e
        e.text.to_s
    end
end


#
# running directly...

if $0 == __FILE__

    if ENV['AMAZON_ACCESS_KEY_ID'] == nil or 
        ENV['AMAZON_SECRET_ACCESS_KEY'] == nil

        puts
        puts "env variables $AMAZON_ACCESS_KEY_ID and $AMAZON_SECRET_ACCESS_KEY are not set"
        puts
        exit 1
    end

    ACTIONS = {
        :list_queues => :list_queues,
        :lq => :list_queues,
        :create_queue => :create_queue,
        :cq => :create_queue,
        :delete_queue => :delete_queue,
        :dq => :delete_queue,
        :flush_queue => :flush_queue,
        :fq => :flush_queue,
        :get_messages => :get_messages,
        :gm => :get_messages,
        :rm => :get_messages,
        :receive_message => :get_messages,
        :delete_message => :delete_message,
        :dm => :delete_message,
        :puts_message => :put_message,
        :pm => :put_message,
        :sm => :send_message,
        :get_queue_attributes => :get_queue_attributes,
        :gqa => :get_queue_attributes,
        :set_queue_attributes => :set_queue_attributes,
        :sqa => :set_queue_attributes,        
    }

    b64 = false
    queue_host = nil
    visibility_timeout = 30
    max_number_of_messages = 10
    
    require 'optparse'

    opts = OptionParser.new

    opts.banner = "Usage: sqs.rb [options] {action} [queue_name] [receipt_handle]"
    opts.separator("")
    opts.separator("   known actions are :")
    opts.separator("")

    keys = ACTIONS.keys.collect { |k| k.to_s }.sort
    keys.each { |k| opts.separator("      - '#{k}'  (#{ACTIONS[k.intern]})") }

    opts.separator("")
    opts.separator("   options are :")
    opts.separator("")

    opts.on("-H", "--host", "AWS queue host") do |host|
        queue_host = host
    end

    opts.on("-h", "--help", "displays this help / usage") do
        STDERR.puts "\n#{opts.to_s}\n"
        exit 0
    end

    opts.on("-b", "--base64", "encode/decode messages with base64") do
        b64 = true
    end

    opts.on("-t MANDATORY", "--timeout MANDATORY", Integer, "Visibility Timeout of a Message in second(max 7200)") do |timeout|
        visibility_timeout = timeout.to_i
        raise "argument 'visibility timeout' should be between 0 and 7200" if max_number_of_messages > 7200 || max_number_of_messages < 0
    end

    opts.on("-m MANDATORY", "--maxmessages MANDATORY", Integer, "Max Number of Messages (max 10)") do |max_number|
        max_number_of_messages = max_number.to_i
        raise "argument 'max number of messages' should be less than 10" if max_number_of_messages > 10
    end

    argv = opts.parse(ARGV)

    if argv.length < 1
        STDERR.puts "\n#{opts.to_s}\n"
        exit 0
    end

    a = argv[0]
    queue_name = argv[1]
    receipt_handle = argv[2]

    action = ACTIONS[a.intern]

    unless action
        STDERR.puts "unknown action '#{a}'"
        exit 1
    end

    qs = SQS::QueueService.new

    STDERR.puts "#{action.to_s}..."

    #
    # just do it

    case action
    when :list_queues, :delete_queue, :flush_queue, :get_queue_attributes

        pp qs.send(action, queue_name)

    when :create_queue

        pp qs.send(action, queue_name, visibility_timeout)
        
    when :set_queue_attributes
      
        pp qs.send(action, queue_name, "VisibilityTimeout" => visibility_timeout)

    when :get_messages
        pp qs.get_messages(queue_name, "VisibilityTimeout" => visibility_timeout, "MaxNumberOfMessages" => max_number_of_messages)

    when :delete_message

        raise "argument 'receipt_handle' is missing" unless receipt_handle
        pp qs.delete_message(queue_name, receipt_handle)

    when :put_message, :send_message

        message = argv[2]

        unless message
            message = ""
            while true
                s = STDIN.gets()
                break if s == nil
                message += s[0..-2]
            end
        end

        message = Base64.encode64(message).strip if b64

        pp qs.put_message(queue_name, message)
    else

        STDERR.puts "not yet implemented..."
    end

end
end

