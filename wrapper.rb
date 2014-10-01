# This software was written by Andrew "Jamoozy" Correa.
#
# This software is distributed under the terms of the GNU General Public
# License, either version 3 or, at your discretion, any later version.

require 'date'
require 'uri'

class IO
  def self.write(fname, content)
    f = File.new(fname, 'w')
    f.write(content)
    f.close()
  end
end

class LangLink
  attr_reader :url     # The URL to link to.

  def initialize(dest, links)
    raise 'Expected string or hash.' unless links.class == Hash or links.class == String

    @url = dest;
    @names = links
  end

  def to_html_for(locale)
    if @names.class == String then
      "<a href=\"#@url\">#@names</a>"
    elsif @names.class == Hash then
      raise "No such locale #{locale}.  Options are: #{@names.keys}" unless @names.keys.include?(locale)
      "<a href=\"#@url\">#{@names[locale]}</a>"
    else
      raise "How did you come this far????  initialize should've thrown a \"wrong type\" error."
    end
  end
end

JS_DIR  = 'js'
IMG_DIR = 'images'
CSS_DIR = '.'

module HTMLUtil
  def php(text)
    "<?php #{text}?>\n"
  end

  def tag(type, attrs = {}, content = '')
    tagf(type, attrs) + "#{content}</#{type}>\n"
  end

  def tagf(type, attrs = {})
    "<#{type}#{(attrs.map {|k,v| " #{k}=\"#{v}\""}).join(' ')}>"
  end

  def method_missing(symbol, *args)
    case args.size
    when 0
      "<#{symbol}>"
    when 1
      tagf(symbol.to_sym, args[0])
    when 2
      tag(symbol.to_sym, args[0], args[1].to_s)
    else
      raise "Can't handle call: #{symbol}(#{args.join(',')})"
    end
  end

  def js(file)
    return <<-eos
      <script type="text/javascript" src="#{JS_DIR}/#{file}"></script>
    eos
  end

  def css(file)
    tagf(:link, {:rel => :stylesheet, :type => 'text/css', :href => "#{CSS_DIR}/#{file}"})
  end

  def img(src)
    tagf(:img, :src => "#{IMG_DIR}/#{src}")
  end

  def validator
     "<a href=\"http://validator.w3.org/check?uri=#@bname?>&charset=%28detect+automatically%29&doctype=Inline&group=0\">VALIDATE!</a>"
  end

  def url_encode str
    # not finshed
    str.gsub(/&/, '%26')
  end

  def html_encode str
    str.gsub(/&/, '&amp;')
  end

  def google_analytics(acct_id)
    return <<-eos
      <script type="text/javascript">
        var _gaq = _gaq || [];
        _gaq.push(['_setAccount', '#{acct_id}']);
        _gaq.push(['_trackPageview']);
        (function() {
          var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
          ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
          var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
        })();
      </script>
    eos
  end

  def to_file(dir, content, block)
    dir += "/#@locale"
    fname = "#{dir}/#@bname.#@ext"
    `mkdir -p #{dir}` unless File.directory?(dir)
    IO.write(fname, wrap(content, block))
  end

  def remove_php_from(content)
    if i = (/(<\?.*\?>)/ =~ content)
      raise "Found '#$1'"
    elsif i = (/(<\?.{1,10})/ =~ content)
      raise "Found open PHP tag: '#$1'"
    elsif i = (/(.{1,10}\?>)/ =~ content)
      raise "Found closing PHP tag: '#$1'"
    end
  end
end

class Wrapper
  include HTMLUtil

  attr_reader :locale, :other_locale, :bname

  def initialize(locale, bname, ext=:html, php_ok=true)
    today = Date.today
    @locale = locale
    @other_locale = ((locale == :de) ? :us : :de)
    @bname = bname
    @ext = ext
    @text = nil
  end

  def last_updated
    @last_updated[@locale]
  end

  def wrap(content, block)
    # Before generating anything ...
    #  ... format the input
    block.call self, content
  end
end

class Options
  attr_accessor :analytics, :verbose, :http_base, :dst, :remote, :tp, :tmp

  def initialize
    @analytics = false
    @verbose = false
    @http_base = nil
    @dst = nil
    @remote = false
    @tp = 'rsync -a'
    @tmp = '.gen/'
  end

  def to_s
    @analytics.to_s + @verbose.to_s + @http_base.to_s + @dst.to_s + @remote.to_s + @tp.to_s + @tmp.to_s
  end
end

class Runner
  attr_reader :options

  def initialize(options, ext=:html, locales=[:de, :us], cps=['*.css', 'images', 'js'], ht='.htaccess')
    @options = options

    @ext = ext
    @locales = locales
    @cps = cps
    @ht = ht
  end

  def run(&block)
    Dir.delete @options.tmp if File.exists? @options.tmp
    Dir.mkdir @options.tmp

    if @locales.size == 0 then
      Dir["*.#@ext"].each do |f|
        generate(nil, f, /(.*)\.#@ext/, block)
      end
    else
      @locales.each do |l|
        Dir["*.#{l}.#@ext"].each do |f|
          generate(l, f, /(.*)\.#{l}\.#@ext/, block)
        end
      end
    end

    @cps.each {|c| cp c }
    htaccess @ht

    transfer
  end

  def generate(locale, fname, re, block)
    content = File.read(fname)
    bname = re.match(fname)[1]
    begin
      wrapper = Wrapper.new(locale, bname, @ext)
      wrapper.to_file(@options.tmp, content, block)
    rescue Exception => e
      puts "Could not parse #{fname}: #{e}"
    end
  end

  def cp(f)
    cmd = "cp -r #{f} #{@options.tmp}"
    puts "Running command: #{cmd}"
    `#{cmd}`
  end

  def htaccess(fname)
    if @options.remote
      tmp_file = "#{@options.tmp}/#{fname}"
      wrote_base = false
      lines = IO.readlines('.htaccess').map do |l|
        if /RewriteBase (.*)/ =~ l
          puts "Warning: replacing base \"#$1\" with \"#{@options.http_base}\"" unless $1 == @options.http_base
          wrote_base = true
          "RewriteBase #{@options.http_base}\n"
        else
          l
        end
      end
      lines.insert(1, "RewriteBase #{@options.http_base}") unless wrote_base

      f = File.new(tmp_file, 'w')
      lines.each{|l| f.write l}
      f.close 
    else
      cp '.htaccess'
    end
  end

  def transfer
    cmds = [ "#{@options.tp} #{@options.tmp}/ #{@options.dst}" ]
    cmds.each do |cmd|
      puts "Running: #{cmd}"
      puts `#{cmd}`
    end
  end
end
