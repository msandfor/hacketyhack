require_relative '../../../lib/code_editor'

#TODO: If I get this far, check whether it works with green shoes

# the code editor tab contents
# the logic behind it is handled in the CodeEditor class
# this should be pure presentation
class HH::SideTabs::Editor < HH::SideTab
  include HH::Markup

  UNNAMED_PROGRAM = "An unnamed program"

  def content
    draw_content
  end

  def load script
    unless @save_button.hidden
      # current script is unsaved
      name = @code_editor.name
      unless confirm("#{name} has not been saved, if you continue \n" +
          " all unsaved modifications will be lost")
        return false
      end
    end
    clear {draw_content script}
    true
  end

  # asks confirmation and then saves (or not if save is)
  def save_if_confirmed
    unless @save_button.hidden
      name = @code_editor.name # || UNNAMED_PROGRAM ? TODO
      question = "I'm going to save modifications to \"#{name}\". Is that okay?\n" +
        "Press OK if it is, and cancel if it's not."
      if confirm(question)
        save name
        true
      else
        false
      end
    end
  end

  def draw_content(script = {})
    @code_editor = HH::Editor::CodeEditor.new(script)

    # basic setup
    # TODO: awkward and clumsy, is there a way to work around this?
    HH::Editor::InsertionDeletionCommand.on_insert_text {|pos, str|  insert_text(pos, str)}
    HH::Editor::InsertionDeletionCommand.on_delete_text {|pos, len|  delete_text(pos, len)}

    # top bar
    @editor = stack :margin_left => 10, :margin_top => 10, :width => 1.0, :height => 92 do
      @sname = subtitle name, :font => "Lacuna Regular", :size => 22,
        :margin => 0, :wrap => "trim"
      @stale = para(@code_editor.last_saved ? "Last saved #{script[:mtime].since} ago." :
        "Not yet saved.", :margin => 0, :stroke => "#39C")
      glossb "New Program", :top => 0, :right => 0, :width => 160 do
        load({})
      end
    end

    # main editor window
    stack :margin_left => 0, :width => 1.0, :height => -92 do
      background white(0.4), :width => 38
      @scroll =
      flow :width => 1.0, :height => 1.0, :margin => 2, :scroll => true do
        stack :width => 37, :margin_right => 6 do
          @ln = para "1", :font => "Liberation Mono", :size => 10, :stroke => "#777", :align => "right"
        end
        stack :width => -37, :margin_left => 6, :margin_bottom => 60 do
          @t = para "", :font => "Liberation Mono", :size => 10, :stroke => "#662",
            :wrap => "trim", :margin_right => 28
          @t.cursor = 0

          # some kind of cursor movement
          def @t.hit_sloppy(x, y)
            x -= 6
            c = hit(x, y)
            if c
              c + 1
            elsif x <= 48
              hit(48, y)
            end
          end

        end

        # mouse movement and clicking in the editor window
        motion do |x, y|
          c = @t.hit_sloppy(x, y)
          if c
            if self.cursor == :arrow
              self.cursor = :text
            end
            if self.mouse[0] == 1 and @clicked
              if @t.marker.nil?
                @t.marker = c
              else
                @t.cursor = c
              end
            end
          elsif self.cursor == :text
            self.cursor = :arrow
          end
        end
        release do
          @clicked = false
        end
        click do |_, x, y|
          c = @t.hit_sloppy(x, y)
          if c
            @clicked = true
            @t.marker = nil
            @t.cursor = c
          end
          update_text
        end
        leave { self.cursor = :arrow }
      end
    end # main window end

    # bottom with save/copy/upload/run buttons
    stack :height => 40, :width => 182, :bottom => -3, :right => 0 do
      @copy_button =
        glossb "Copy", :width => 60, :top => 2, :left => 70 do
          save(nil)
        end

      @save_button =
        glossb "Save", :width => 60, :top => 2, :left => 70, :hidden => true do
          if save(script[:name])
            timer 0.1 do
              @save_button.hide
              @copy_button.show
              @save_to_cloud_button.show
            end
          end
        end

      @save_to_cloud_button =
        glossb "Upload", :width => 70, :top => 2, :left => 0 do
          if HH::PREFS['username'].nil?
            alert("To upload, first connect your account on hackety-hack.com by clicking Preferences near the bottom left of the window.")
          else
            hacker = Hacker.new :username => HH::PREFS['username'], :password => HH::PREFS['password']
            hacker.save_program_to_the_cloud(@code_editor.name, @code_editor.script) do |response|
              if response.code == "200" || response.code == "302"
                alert("Uploaded!")
              else
                alert("There was a problem, sorry!")
              end
            end
          end
        end

      glossb "Run", :width => 52, :top => 2, :left => 130 do
        eval(@code_editor.script, HH.anonymous_binding)
      end

    end

    # updating the time
    every 20 do
      if script[:mtime]
        @stale.text = "Last saved #{@code_editor.last_saved} ago."
      end
    end

    keypress do |k|
      onkey(k)
      if @t.cursor_top < @scroll.scroll_top
        @scroll.scroll_top = @t.cursor_top
      elsif @t.cursor_top + 92 > @scroll.scroll_top + @scroll.height
        @scroll.scroll_top = (@t.cursor_top + 92) - @scroll.height
      end

    end

    # for samples do not allow to upload to cloud when just opened
    @save_to_cloud_button.hide if script[:sample]
    update_text
  end

  # saves the file, asks for a new name if a nil argument is passed
  def save name
    if name.nil?
      msg = ""
      while true
        name = ask(msg + "Give your program a name.")
        # TODO make more beautiful
        break if name.nil? or not HH.script_exists?(name)
        msg = "You already have a program named '" + name + "'.\n"
      end
    end

    if name
      @sname.text = name
      last_saved = @code_editor.save name
      @stale.text = "Last saved #{last_saved.since} ago."
      true
    else
      false
    end
  end

  def update_text
    @t.replace *highlight(@code_editor.script, @t.cursor)
    @ln.replace [*1..(@code_editor.script.count("\n")+1)].join("\n")
  end

  def text_changed
    if @save_button.hidden
      @copy_button.hide
      @save_button.show
      @save_to_cloud_button.hide
    end
  end

  # called when the user wants to insert text
  def handle_text_insertion text
      pos, len = @t.highlight; # TODO: WTF ; ?
      handle_text_deletion(pos, len) if len > 0

      insert_text pos, text
  end

  # called when the user wants to delete text
  def handle_text_deletion pos, len
    delete_text pos, len
  end

  def insert_text pos, text
    @code_editor.insert_text pos, text
    @t.cursor = pos + text.size
    @t.cursor = :marker # XXX ???
  end

  def delete_text pos, len
    @code_editor.delete_text pos, len
    @t.cursor = pos
    @t.cursor = :marker
    #update_text
  end

  # find the indentation level at the current cursor or marker
  # whatever occurs first
  # the result is the number of spaces
  def indentation_size
    # TODO marker
    pos = @code_editor.script.rindex("\n", @t.cursor-1)
    return 0 if pos.nil?

    pos += 1

    ind_size = 0
    while @code_editor.script[pos, 1] == ' '
      ind_size += 1
      pos += 1
    end
    ind_size
  end

  def onkey(key)
    case key
    when :shift_home, :shift_end, :shift_up, :shift_left, :shift_down, :shift_right
      @t.marker = @t.cursor unless @t.marker
    when :home, :end, :up, :left, :down, :right
      @t.marker = nil
    end

    # keypress wilderness
    case key
    when String
      if key == "\n"
        # handle indentation
        ind = indentation_size
        handle_text_insertion(key)
        handle_text_insertion(" " * ind) if ind > 0
      else
        # usual case
        handle_text_insertion(key)
      end
    when :backspace, :shift_backspace, :control_backspace
      if @t.cursor > 0 and @t.marker.nil?
        @t.marker = @t.cursor - 1 # make highlight length at least 1
      end
      sel = @t.highlight
      if sel[0] > 0 or sel[1] > 0
        handle_text_deletion(*sel)
      end
    when :delete
      sel = @t.highlight
      sel[1] = 1 if sel[1] == 0
      handle_text_deletion(*sel)
    when :tab
      handle_text_insertion("  ")
#      when :alt_q
#        @action.clear { home }
    when :control_a, :alt_a
      @t.marker = 0
      @t.cursor = @code_editor.script.length
    when :control_x, :alt_x
      if @t.marker
        sel = @t.highlight
        self.clipboard = @code_editor.script[*sel]
        if sel[1] == 0
          sel[1] = 1
          raise "why did this happen??"
        end
        handle_text_deletion(*sel)
      end
    when :control_c, :alt_c, :control_insertadd_characte
      if @t.marker
        self.clipboard = @code_editor.script[*@t.highlight]
      end
    when :control_v, :alt_v, :shift_insert
      handle_text_insertion(self.clipboard) if self.clipboard
    when :control_z
      debug("undo!")
      @code_editor.undo_command
    when :control_y, :alt_Z, :shift_alt_z
      debug "redo!"
      @code_editor.redo_command
    when :shift_home, :home
      nl = @code_editor.script.rindex("\n", @t.cursor - 1) || -1
      @t.cursor = nl + 1
    when :shift_end, :end
      nl = @code_editor.script.index("\n", @t.cursor) || @code_editor.script.length
      @t.cursor = nl
    when :shift_up, :up
      if @t.cursor > 0
        nl = @code_editor.script.rindex("\n", @t.cursor - 1)
        if nl
          horz = @t.cursor - nl
          upnl = @code_editor.script.rindex("\n", nl - 1) || -1
          @t.cursor = upnl + horz
          @t.cursor = nl if @t.cursor > nl
        end
      end
    when :shift_down, :down
      nl = @code_editor.script.index("\n", @t.cursor)
      if nl
        if @t.cursor > 0
          horz = @t.cursor - (@code_editor.script.rindex("\n", @t.cursor - 1) || -1)
        else
          horz = 1
        end
        dnl = @code_editor.script.index("\n", nl + 1) || @code_editor.script.length
        @t.cursor = nl + horz
        @t.cursor = dnl if @t.cursor > dnl
      end
    when :shift_right, :right
      @t.cursor += 1 if @t.cursor < @code_editor.script.length
    when :shift_left, :left
      @t.cursor -= 1 if @t.cursor > 0
    end
    if key
      text_changed
    end

    update_text
  end

end

