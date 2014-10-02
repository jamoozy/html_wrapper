# This software was written by Andrew "Jamoozy" Correa.
#
# This software is distributed under the terms of the GNU General Public
# License, either version 3 or, at your discretion, any later version.

require 'fileutils'
require 'date'
require 'uri'

# Convenience class to write contents to a file simply and easily.
class IO
  # Writes <tt>content</tt> to <tt>fname</tt>.
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

  # Writes the language link in HTML based on the locale.  This acts
  # differently based on how this <tt>LangLink</tt> was initialized; if
  # <tt>links</tt> in the constructor was a <tt>Hash</tt>, then local must not
  # be <tt>nil</tt> -- it will be used as the index into the links.  If
  # <tt>links</tt> was a string, however, then the <tt>locale</tt> argument
  # will be ignored.
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

JS_DIR  = 'js'        # dir to put JavaScript in.
IMG_DIR = 'images'    # dir to put images in.
CSS_DIR = '.'         # dir to put CSS in.

# Module to make easy HTML tags.
module HTMLUtil
  # Makes a PHP tag with the given PHP in it.
  #   text:: The text of the PHP.
  def php(text)
    "<?php #{text}?>\n"
  end

  # Creates open and closing tags of type <tt>type</tt> with the given
  # attributes and containing the given content.
  #   type:: The type of the tags.
  #   attrs:: The attributes.
  #   content:: The content to put between the tags.
  def tag(type, attrs = {}, content = '')
    tagf(type, attrs) + "#{content}</#{type}>\n"
  end

  # Creates an opening tag of the given type with the given attributes.
  #   type:: The type of the tag.
  #   attrs:: The tag's attributes
  def tagf(type, attrs = {})
    "<#{type}#{(attrs.map {|k,v| " #{k}=\"#{v}\""}).join(' ')}>"
  end

  # Catch-all equivalent to simply writing <tt><symbol></tt>, calling
  # <tt>tagf(symbol, args[0])</tt> or calling <tt>tag(symbol, args[0],
  # args[1])</tt>, depending on how many arguments <tt>args</tt> has.
  #   symbol:: The tag type to create.
  #   args:: empty/missing, a hash corresponding to the args to pass to
  #          <tt>tagf</tt>, or a hash corresponding to the args and a string
  #          representing the content.
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

  # Emit a javascript <tt>script</tt> tag for the given file (within JS_DIR).
  def js(file)
    return <<-eos
      <script type="text/javascript" src="#{JS_DIR}/#{file}"></script>
    eos
  end

  # Emit a CSS <tt>link</tt> tag for the given file (within CSS_DIR).
  def css(file)
    tagf(:link, {:rel => :stylesheet, :type => 'text/css', :href => "#{CSS_DIR}/#{file}"})
  end

  # Emit an <tt>img</tt> tag for the given src file (within IMG_DIR).
  def img(src)
    tagf(:img, :src => "#{IMG_DIR}/#{src}")
  end

  # Add a validator string to make sure the HTML5 is kosher.
  def validator
     "<a href=\"http://validator.w3.org/check?uri=#@bname?>&charset=%28detect+automatically%29&doctype=Inline&group=0\">VALIDATE!</a>"
  end

  # Encodes a string to a URL -- not yet finished.
  def url_encode str
    # not finshed
    str.gsub(/&/, '%26')
  end

  # Encodes a string to HTML.
  def html_encode str
    str.gsub(/&/, '&amp;')
  end

  # Emits the Google Analytics string with the given account ID.
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

  # Write content to file.  Handles locales.
  #   dir:: The directory to write to.
  #   content:: The content to put in the file.
  #   block:: The user-written block to emit the HTML.
  def to_file(dir, content, block)
    dir += "/#@locale" unless @local == nil
    fname = "#{dir}/#@bname.#@ext"
    `mkdir -p #{dir}` unless File.directory?(dir)
    IO.write(fname, wrap(content, block))
  end

  # Raises an exception if <tt>content</tt> has PHP in it.
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

# Wraps content in a common header and footer.
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

# Keeps track of several options useful for running a wrapper.
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

# Runs a wrapper on a set of files, wrapping each in a common header and
# footer, performing other useful tasks like linking the pages together, and
# running a user-written code block.
class Runner
  attr_reader :options

  def initialize(options, dir='./', ext=:html, locales=[:de, :us], cps=['*.css', 'images', 'js'], ht='.htaccess')
    @options = options

    @dir = dir
    @ext = ext
    @locales = locales
    @cps = cps
    @ht = ht
  end

  # Runs the runner, which in turn finds all the files to be processed, runs
  # the block on each file, and emits it to a file.
  def run(&block)
    FileUtils.rm_r @options.tmp if File.exists? @options.tmp
    Dir.mkdir @options.tmp

    if @locales.size == 0 then
      Dir["#@dir/*.#@ext"].each do |f|
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

  # Wraps the content from <tt>fname</tt> in the common header and footer,
  # by running the user-written block on it.
  #   locale:: The locale this is for. (ignored if no locales)
  #   fname:: The file with the content to wrap.
  #   re:: The regular expression used to find the file's base name.
  #   block:: The user-written block.
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

  # Copies a file to the tmp directory in preparation for transfer.
  def cp(f)
    cmd = "cp -r #{f} #{@options.tmp}"
    puts "Running command: #{cmd}"
    `#{cmd}`
  end

  # Copies over the <tt>.htaccess</tt> file, replacing the http_base if
  # necessary.
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

  # Transfers the contents of the website contained in the tmp dir to their
  # destination.
  def transfer
    cmds = [ "#{@options.tp} #{@options.tmp}/ #{@options.dst}" ]
    cmds.each do |cmd|
      puts "Running: #{cmd}"
      puts `#{cmd}`
    end
  end
end
