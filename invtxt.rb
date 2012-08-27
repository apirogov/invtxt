#!/usr/bin/env ruby
#invtxt.rb
#CLI tool to manage the home inventory, inspired by todo.sh
#Copyright (C) 2012 Anton Pirogov, licensed under the GPLv3
#see README for info about the file format
#requires imagemagick to be installed for picture modifications!
#
#TODO: automatic intelligent recursive tag/category/alias rename/removal?
#      unit tests
#----
require 'fileutils'

#monkey patching useful+necessary functions to String
class String
def colorize(text, color_code) "\e[#{color_code}m#{text}\e[0m" end
def bold; colorize(self, 1) end
def black; colorize(self, 30) end
def red; colorize(self, 31) end
def green; colorize(self, 32) end
def yellow; colorize(self, 33) end
def blue; colorize(self, 34) end
def magenta; colorize(self, 35) end
def cyan; colorize(self, 36) end
def white; colorize(self, 37) end

def is_num?
  n = Integer self
  return true
rescue ArgumentError
  return false
end
end

#----
#CONFIG LOADING

#try to load, write and use defaults if not found
CONFPATH=Dir.home+'/.invtxt'
if File.exists?(CONFPATH)
  load CONFPATH
else
  File.write CONFPATH, DATA.readlines.join
end

#set default values for unset constants
INVPATH ||= Dir.home+'/inventory'
JPGSIZE ||= 1000
JPGQUAL ||= 75
VIEWER  ||= 'gpicview'
SORTEDP   = true  unless defined? SORTEDP
PRETTYP   = true  unless defined? PRETTYP
NOMAGICK  = false unless defined? NOMAGICK

#----
#CONSTANTS (not for user-modification)

#derivative consts
INVFILE = INVPATH+'/inv.txt'
PICPATH = INVPATH+'/pics'

#used prefixes and seperators for metadata and stuff
METASEP = '->'
CATPREF = '@'
TAGPREF = '#'
ALSPREF = '*'
PICPREF = '+'
ALLPREFS = CATPREF+TAGPREF+ALSPREF+PICPREF #all prefixes together for matching

#----
#CLASSES AND FUNCTIONS

class Inventory
  attr_reader :readsuccess, :records

  def initialize(file)
    @readsuccess = false
    @readsuccess = open file
  end

  #load inventory text file and parse it
  #return success boolean
  def open(file)
    @records = File.readlines(file)
    @records.delete_if {|i| /^\s*$/.match i}
    @records.map!{|i| i.chomp.strip}
    @records.map!{|i| Item.new i}
    @records.each_with_index{|e,i| e.line = i+1}
    return true
  rescue Exception => e
    #puts e.backtrace
    @records = []
    return false
  end

  #save inventory back to textfile
  #return success boolean
  def save(file)
    File.rename(file, file+'.bak')
    begin
      File.write(file, @records.map(&:to_s).map(&:strip).select{|l| l!=''}.join("\n"))
    rescue
      File.rename(file+'.bak', file)
      return false
    end
    File.delete(file+'.bak')
    return true
  rescue
    return false
  end

  #prints an array of items (used for ls and similar)
  def print(items, sorted=SORTEDP, pretty=PRETTYP)
    items = items.sort_by{|a| a.category.to_s} if sorted #sort by categories if neccessary
    npad = items.size.to_s.length #number width with leading zeros

    if pretty
      lines = items.map{|e| ("%0#{npad}d " % e.line).bold.white + e.to_s_pretty(npad)}
      puts lines.join("\n")
    else
      lines = items.map{|e| ("%0#{npad}d " % e.line) + e.to_s}
      puts lines.join("\n")
    end

    puts "--"
    puts items.size.to_s+' of '+@records.size.to_s+' items shown'
  end

  #return an array of all known tags
  def tags
    @records.map(&:tags).reduce(&:+).uniq
  end

  #return an array of all known categories
  def categories
    @records.map(&:category).uniq-[nil]
  end

  #return an array of all used aliases
  def aliases
    @records.map(&:alias).uniq-[nil]
  end

  def alias_free?(als)
    !aliases.index(als)
  end

  #return only items containing a given string
  def filter(str)
    @records.select{|i| i.to_s.scan(/#{Regexp.escape str}/i).size>0}
  end

  #return only items with a set required amount where
  #the available amount is below that required value
  def filter_deficit
    @records.select do |i|
      if i.required.nil?
        false
      else
        i.amount<i.required
      end
    end
  end

  #interface to access records by line number or alias, as provided by the CLI
  #returns the found item or nil
  def get(str)
    if str.is_num?
      n = str.to_i
      if (n>0 && n<=@records.size)
        return @records[n-1]
      else
        return nil
      end
    else
      #prepend alias prefix if not written by user (convenience)
      str=ALSPREF+str if str[0]!=ALSPREF

      @records.each{|e| return e if e.alias==str}
      return nil #not found
    end
  end

  #helper func for cli interface - try to find given item
  #or show error and die (radical, unforgiving Inventory.get wrapper)
  def getitem(str)
    if str.nil?
      puts 'No item specified! Use line number or alias!'
      exit 1
    end
    entry = get(str)
    if entry.nil?
      puts 'Item not found! Use line number or alias!'
      exit 1
    end

  return entry
end

  #move all unreferenced pics to garbage dir
  #to be reviewed and deleted
  def clean_picdir
    reflist = @records.map(&:pics).reduce(&:+).uniq.map{|e| e[1..-1]+'.jpg'}
    piclist = Dir.new(PICPATH).entries-['.','..']
    toclean = piclist-reflist

    if toclean.empty?
      puts "No orphaned pictures found :)"
      return
    end

    gpath = INVPATH+'/garbage'
    if Dir.exists? gpath
      puts 'Please review the pictures from the last cleaning and remove the garbage directory!'
      exit 1
    end

    Dir.mkdir gpath
    toclean.each{|e| FileUtils.mv PICPATH+'/'+e, gpath+'/' }
    puts 'Orphaned pictures moved to garbage directory! Please check and delete them!'
  rescue
    puts 'Could not move pictures to garbage! Check permissions?'
    exit 1
  end

  #takes a file name, shrinks if neccessary and possible
  #imports to pics folder, returns the "+picname" or nil
  def addpic(file)
    filepath = File.expand_path file

    usemagick = !NOMAGICK
    begin
      `identify` if usemagick
    rescue
      puts 'Warning: imagemagick not found! Picture will be imported, but not modified!'
      puts 'You may set NOMAGICK=true in the config, to supress this warning.'
      usemagick = false
    end

    if !usemagick && file[-4..-1]!='.jpg'
      puts 'Error: Without imagemagick only .jpg files are supported!'
      puts file+' skipped!'
      return nil
    end

    #calc for shrinking if magick enabled
    percent = 100
    if usemagick
      res = `identify -format %G #{filepath} 2>&1`
      if res.index('identify:')
        puts 'Error: invalid picture!'
        puts file+' skipped!'
        return nil
      end

      longside = res.chomp.split('x').map(&:to_i).max
      percent = (JPGSIZE.to_f/longside*100).to_i if longside > JPGSIZE
    end

    id = genpicid       #free numeric id
    newpath = PICPATH+'/'+id+'.jpg' #filename to be used for the copy

    if usemagick
      result = `convert -resize #{percent}% -quality #{JPGQUAL} #{filepath} #{newpath}`
      if result != ""
        puts 'Imagemagick shrinking and import failed!'
        puts file+' skipped!'
        return nil
      end
    else
      begin
        FileUtils.cp filepath, newpath
      rescue
        puts 'Importing the picture failed!'
        puts file+' skipped!'
        return nil
      end
    end

    return '+'+id #success
  end

  private
  #find a free numeric id name for a picture to be imported
  #returned as string
  def genpicid
    taken = Dir.new(PICPATH).entries-['.','..']
    taken.map!{|p| p[0..-5]}.select!(&:is_num?)

    i=1
    while taken.index i.to_s
      i += 1
    end
    return i.to_s
  end
end

class Item
  attr_accessor :line #just for printing and finding, not saved
  attr_accessor :amount, :required, :alias, :text
  attr_reader   :meta #custom writer specified below
  attr_reader   :category, :tags, :refs, :pics #derivative from meta

  #assumes well formed data! no checking, no guarantee for correct interpretation
  #rules: starting with optional amount/required value, like (3) or (5/6)
  #       followed by an optional alias, followed by optional arbitrary text
  #       followed by the optional meta section, which is lead by the meta-separator
  #       followed by following unordered, optional items:
  #       one category and arbitrary number of tags, pics, refs
  #       if more than one category present, using first one
  #       any other meta data and categories removed on saving
  def initialize(str)
    str = str.chomp.strip
    str = str.split(/\s+#{METASEP}\s+/)

    #split away meta
    if str.size > 1
      @meta = str[1].strip
    end
    rest = str[0]

    #read amount and required amount, if found
    numregex = /^(\(\d+(\/\d+)?\))/
    nums = rest.match(numregex).to_s
    if nums != ''
      rest = rest[(nums.length)..-1]
      nums = nums.scan(/\d+/)
      @amount, @required = nums.map(&:to_i)
    end

    #read alias if set
    rest.strip!
    @alias = rest.scan(tokregex ALSPREF).shift
    unless @alias.nil?
      rest = rest[(@alias.length)..-1]
    end

    #read normal description text
    rest.strip!
    @text = rest if rest!=''

    #parse metadata if present
    @tags = @pics = @refs = []
    update_meta_tokens
  end

  def meta=(str)
    @meta = str
    update_meta_tokens
  end

  def update_meta_tokens
    return if @meta.nil?
    @category = @meta.scan(tokregex CATPREF).shift
    @tags = @meta.scan(tokregex TAGPREF)
    @pics = @meta.scan(tokregex PICPREF)
    @refs = @meta.scan(tokregex ALSPREF)
  end

  #stringify back to inventory file format line for saving
  def to_s
    str = ''
    if @required.nil?
      unless @amount.nil?
        str += "(#{@amount}) "
      end
    else
      if @amount.nil?
        str += "(1/#{@required}) "
      else
        str += "(#{@amount}/#{@required}) "
      end
    end

    str += @alias+' ' unless @alias.nil?
    str += @text.strip+' ' unless @text.nil?

    unless @meta.to_s.strip=='' #clean up and sanitize metadata
      str += METASEP.to_s+' '+@category.to_s+' '+@tags.join(' ')+' '
      str += @refs.join(' ')+' '+@pics.join(' ')
    end

    return str
  end

  #pretty print with ansi colors in multiple lines and aligned
  #to be used just for user output by the Inventory.print routine, not serialization!
  #dear contributor, sorry for the fuglyness :/
  def to_s_pretty(pad)
    nums = nil
    if @required.nil?
      unless @amount.nil?
        nums = "(#{@amount})"
      end
    else
      if @amount.nil?
        nums = "(1/#{@required})"
      else
        nums = "(#{@amount}/#{@required})"
      end
    end

    if @amount || @required
      nums = @amount.to_i<@required.to_i ? nums.bold.red : nums.bold.green
    end

    unless @alias.nil?
      als = @alias
    end

    txt = @text.strip unless @text.nil?
    met = @meta.strip.gsub(tokregex ALLPREFS) do |match|
      case match[0]
      when ALSPREF
        match.yellow
      when CATPREF
        match.bold.cyan
      when TAGPREF
        match.bold.magenta
      when PICPREF
        match.bold.blue
      end
    end unless @meta.nil?

    padding = ' '*(pad+1)
    rightpadsz = 30
    numsadded = false
    str = ''
    if als
      str += als.bold.yellow
      if nums
        rightpad = rightpadsz-als.length
        rightpad = 1 if rightpad<0
        str += (' '*rightpad)+nums
        numsadded = true
      end
    end

    if ((txt && txt.length>rightpadsz) || !txt) && !numsadded
        str += (' '*rightpadsz)+nums
        numsadded = true
    end

    str += "\n"+padding if str != '' && (txt || met)

    if txt
      str += txt
      if !numsadded && nums
        rightpad = rightpadsz-str.length
        rightpad = 1 if rightpad<0
        str += (' '*rightpad)+nums
        numsadded = true
      end

      str += "\n"+padding if met
    end

    str += met if met
    return str
  end

  private
  #help function to parse the meta tokens
  def self.tokregex(pref)
    /[#{Regexp.escape pref}]\w+/
  end
  def tokregex(pref) self.class.tokregex pref end
end

def show_help
  puts <<eos
CLI tool to manage the home inventory, inspired by todo.sh
Copyright (C) 2012 Anton Pirogov, licensed under the GPLv3

Usage: (ITEM means - either the line number or the specified alias)
#{$0} ls [filter]
  => show items (if filter given, only containing given string, case-insensitive)
#{$0} lsdeficit
  => print all items with set amount and required values where amount<required
#{$0} lscat
  => print all known category names
#{$0} lstag
  => print all known tag names
#{$0} lsals
  => print all known alias names
#{$0} lsref ITEM
  => print all items referenced by ITEM

#{$0} ITEM num  VALUE (absolute value or relative (e.g. +3))
#{$0} ITEM req  VALUE
#{$0} ITEM als  VALUE
#{$0} ITEM text "name description"
#{$0} ITEM meta "location *reference +pic.jpg +pic2.jpg"
  => modify parts of an item record ('unset' as value will unset that part)

#{$0} ITEM rm
  => remove specified item entry entirely from inventory
#{$0} add "inventory record string"
  => Add new record to inventory list (please use the correct format)

#{$0} pics show ITEM
  => show all imported pictures for an item with VIEWER
#{$0} pics add ITEM PICTURES...
  => take picture(s), shrink to a useful size,
     rename to a short numeric value, save as jpg
     attach to meta data string of given ID
#{$0} pics clean
  => remove pics not associated with any item record (garbage collection)
eos
end

#----
#MAIN

#abort if inventory directory not found to prevent a mess
unless Dir.exists? INVPATH
  puts 'Error: specified inventory directory'
  puts INVPATH
  puts 'not found!'
  exit 1
end

#initialize new inventory files if stuff not found
begin
  Dir.mkdir(PICPATH) unless Dir.exists? PICPATH
  File.write(INVFILE, '') unless File.exists? INVFILE
rescue
  puts 'Error: Could not initialize inventory files! Check permissions?'
  exit 1
end

#load data
inv = Inventory.new INVFILE
unless inv.readsuccess
  puts 'Error: could not read inv.txt file! Check permissions?'
  exit 1
end

#execute CLI user request
action = ARGV.shift
case action
  when 'ls'
    if ARGV.empty?
      inv.print inv.records
    else
      inv.print inv.filter(ARGV.shift)
    end
  when 'lsdeficit'
    inv.print inv.filter_deficit
  when 'lscat'
    puts inv.categories.join(' ')
  when 'lstag'
    puts inv.tags.join(' ')
  when 'lsals'
    puts inv.aliases.join(' ')
  when 'lsref'
    entry = inv.getitem ARGV.shift
    inv.print entry.refs.map{|e| inv.get e}.select{|e| e}

  when 'add'
    entry = ARGV.shift
    inv.records << Item.new(entry)
  when 'pics'
    cmd = ARGV.shift
    if cmd.nil?
      puts 'possible actions:', '  pics add ITEM FILE1 FILE2...'
      puts '  pics show ITEM', '  pics clean'
      exit 1
    end

    case cmd
    when 'add'
      entry = inv.getitem ARGV.shift

      files = ARGV
      if files.size==0
        puts 'No picture files specified!'
        exit 1
      end

      imported = files.map{|f| inv.addpic f}
      imported.delete nil #remove failed

      #associate with item record
      entry.meta ||= ""
      entry.meta += ' '+imported.join(' ')

    when 'show'
      entry = inv.getitem ARGV.shift

      if entry.pics.empty?
        puts 'Item has no associated pictures!'
        exit 1
      end

      #show all associated pictures (open a viewer for each pic in background)
      entry.pics.each{|e| system "#{VIEWER} #{PICPATH+'/'+e[1..-1]+".jpg"} &"}

    when 'clean'
      inv.clean_picdir

    else
      puts 'Unknown action!'
      exit 1
    end

  when '-h'
    show_help
  else
    if action.nil?
      puts 'Please specify an action!', "Try '#{$0} -h' for more information."
      exit 1
    end

    entry = inv.getitem action  #assume it's an item name or line

    #ID or alias given -> modification action
    subaction = ARGV.shift
    if subaction.nil?
      puts 'possible actions:', '  ITEM text|meta|num|req|als VALUE'
      puts '  ITEM text|meta|num|req|als unset', '  ITEM rm'
      exit 1
    end

    if subaction == 'rm'
      inv.records.delete entry
      puts 'The following entry has been removed:', entry.to_s
      puts 'If this was a mistake, re-add the item by using the line above.'

    else
      value = ARGV.shift
      if value.nil?
        puts 'No value specified!'
        exit 1
      end

      case subaction
      when 'num'
        if value=='unset'
          entry.amount = nil
        else
          unless value.is_num? || value[1..-1].is_num?
            puts 'Invalid number!'
            exit 1
          end

          if value[0]=='+' || value[0]=='-' #relative
            value = value[1..-1] if value[0]=='+'
            entry.amount += value.to_i
          else #absolute
            entry.amount = value.to_i
          end
        end

      when 'req'
        if value=='unset'
          entry.required = nil
        else
          unless value.is_num?
            puts 'Invalid number!'
            exit 1
          end
          entry.required = value.to_i
        end

      when 'als'
        if value=='unset'
          entry.alias = nil
        else
          #prepend alias prefix if not written by user (convenience)
          value=ALSPREF+value if value[0]!=ALSPREF

          if inv.alias_free? value
            entry.alias = value
          else
            puts 'This alias is already in use by another item!'
            exit 1
          end
        end

      when 'text'
        entry.text = value=='unset' ? nil : value

      when 'meta'
        entry.meta = value=='unset' ? nil : value

      else
        puts 'Unknown action!'
        exit 1
      end
    end
end

#at last save changes
unless inv.save INVFILE
  puts 'Error: Could not save to inv.txt file! Check permissions?'
  exit 1
end

__END__
#invtxt.rb configuration file
#these are the default values, uncomment and change them to your liking

#the path where the inventory data is stored
INVPATH  = Dir.home+'/inventory'

#if true, the items will be ordered by category
#if false, they will be ordered as they appear in the file
SORTEDP  = true

#if true, colorization and fancy output will be used
#if false, it's basically - what you see in the file is what you get
PRETTYP  = true

#Target picture width and quality for imported pictures
#applied only to pictures which are too big
JPGSIZE = 1000
JPGQUAL = 75

#Picture viewer to be used with the 'pics show' command
VIEWER   = 'gpicview'

#Set to true if no imagemagick present or desired.
#Then the pictures will be imported untouched and
#you also only can use JPEG files for import
NOMAGICK = false
