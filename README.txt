
= rufus-sqs for SQS 2008-01-01 version

rufus-sqs version 0.8 uses Amazon SQS API version 2006-04-01, which may become obsolete on May 6, 2009. This version calls SQS API version 2008-01-01 which is the latest one as of August 2008.


== getting it

    Currently, you need to download the gem file from GitHub, unless the original authors create an official gem to place at rubyforge.org.
    Download the compressed files, then rake gem to produce the gem file rufus-sqs-0.8.gem. sudo gem install rufus-sqs-0.9.gem

== usage

At first, 'rufus-sqs' expects to find the Amazon WebServices keys in four environment variables : AMAZON_ACCESS_KEY_ID and AMAZON_SECRET_ACCESS_KEY

(Like the gem "aws-s3" http://amazon.rubyforge.org/ does).


For example, I store them in a file named .amazon that gets loaded when necessary :

    export AMAZON_ACCESS_KEY_ID=17r37R45YZDY252G2
    export AMAZON_SECRET_ACCESS_KEY=ibMU8QfPDB5sCUgS0NLbScA2/OChUHNy


Some example code (replace the queue name "yourtestqueue" with something else):
    
    require 'rubygems'
    require 'rufus/sqs'

    qs = Rufus::SQS::QueueService.new
    
    qs.create_queue "yourtestqueue"
    
    msg = "hello SQS world !"
    
    if qs.put_message "yourtestqueue", msg
      
      msgs = qs.get_messages "yourtestqueue"
    
      puts msgs[0].message_body
        # => 'hello SQS world !"
    
    end

    qs.delete_queue "yourtestqueue"

more at Rufus::SQS::QueueService


= dependencies

The gem 'rufus-verbs' (http://rufus.rubyforge.org/rufus-verbs) and its dependencies.


== mailing list

On the rufus-ruby list[http://groups.google.com/group/rufus-ruby] :

    http://groups.google.com/group/rufus-ruby


== issue tracker

http://rubyforge.org/tracker/?atid=18584&group_id=4812&func=browse


== source

http://github.com/jmettraux/rufus-sqs

    git clone git://github.com/jmettraux/rufus-sqs.git


== author

John Mettraux, jmettraux@gmail.com 
http://jmettraux.wordpress.com

Koichi Hirano, internalist aat gmail doot com
http://oneagileteam.com

== the rest of Rufus

http://rufus.rubyforge.org


== license

MIT

