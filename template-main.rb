#!/usr/bin/env ruby
##############################################################################
# Copyright (c) 2006 Camera Bits, Inc.  All rights reserved.
##############################################################################


TEMPLATE_DISPLAY_NAME = "PhotoShelter"  # must be same for uploader and conn. settings


##############################################################################
## Connection Settings template

class PShelterConnectionSettingsUI

  include PM::Dlg
  include AutoAccessor
  include CreateControlHelper

  def initialize(pm_api_bridge)
#dbgprint "PShelterConnectionSettingsUI.initialize()"
    @bridge = pm_api_bridge
  end

  def create_controls(parent_dlg)
    dlg = parent_dlg
    create_control(:setting_name_static,    Static,       dlg, :label=>"PhotoShelter Connection Setting Name:")
    # the combo/edit/buttons are arranged in tab order
    create_control(:setting_name_combo,     ComboBox,     dlg, :editable=>true, :sorted=>true, :persist=>false)
    create_control(:login_edit,             EditControl,  dlg, :value=>"", :persist=>false)
    create_control(:password_edit,          EditControl,  dlg, :value=>"", :password=>true, :persist=>false)
    create_control(:setting_new_btn,        Button,       dlg, :label=>"New")
    create_control(:setting_delete_btn,     Button,       dlg, :label=>"Delete")
    create_control(:login_static,           Static,       dlg, :label=>"PhotoShelter Account Login:")
    create_control(:password_static,        Static,       dlg, :label=>"Password:")
  end

  def layout_controls(container)
    sh, eh = 20, 24
    c = container
    c.set_prev_right_pad(5).inset(10,10,-10,-10).mark_base
    c << @setting_name_static.layout(0, c.base, -1, sh)
    c.pad_down(0).mark_base
    c << @setting_name_combo.layout(0, c.base, -150, eh)
      c << @setting_new_btn.layout(-140, c.base, -80, eh)
        c << @setting_delete_btn.layout(-70, c.base, -1, eh)
    c.pad_down(15).mark_base
    c << @login_static.layout(0, c.base, 200, sh)
      c << @password_static.layout(210, c.base, 70, sh)
    c.pad_down(0).mark_base
    c << @login_edit.layout(0, c.base, 200, eh)
      c << @password_edit.layout(210, c.base, 120, eh)
    c.pad_down(0).mark_base
  end
end


class PShelterConnectionSettings

  # must include PM::FileUploaderTemplate so that
  # the template manager can find our class in
  # ObjectSpace
  include PM::ConnectionSettingsTemplate

  DLG_SETTINGS_KEY = :connection_settings_dialog

  def self.template_display_name  # template name shown in dialog list box
    TEMPLATE_DISPLAY_NAME
  end

  def self.template_description  # shown in dialog box
    "PhotoShelter Connection Settings"
  end

  def self.fetch_settings_data(serializer)
    if serializer.did_load_from_disk?
      dat = serializer.fetch(DLG_SETTINGS_KEY, :settings) || {}
      SettingsData.deserialize_settings_hash(dat)
    else
      bridge = Thread.current[:sandbox_bridge]  # || Thread.current[:bridge]
      legacy = bridge.read_legacy_pshelter_conn_settings
      settings = SettingsData.convert_legacy_pshelter_conn_settings(legacy)
      # import the legacy settings into the serializer
      settings_dat = SettingsData.serialize_settings_hash(settings)
      serializer.store(DLG_SETTINGS_KEY, :settings, settings_dat)
      settings
    end
  end

  def self.store_settings_data(serializer, settings)
    settings_dat = SettingsData.serialize_settings_hash(settings)
    serializer.store(DLG_SETTINGS_KEY, :settings, settings_dat)
  end

  def self.fetch_selected_settings_name(serializer)
    serializer.fetch(DLG_SETTINGS_KEY, :selected_item)  # might be nil
  end

  class SettingsData
    attr_accessor :login, :password

    def initialize(login, password)
      @login = login
      @password = password
    end

    def appears_valid?
      ! ( @login.nil?  ||  @password.nil?  ||
          @login.to_s.strip.empty?  ||  @password.to_s.strip.empty? )
    end

    # Convert a hash of SettingsData, to a hash of
    # arrays, and encrypt the password along the way.
    #
    # NOTE: We ditch the SettingsData, because its module
    # name would end up being written out with the YAML, but
    # templates are in a sandbox whose module name includes
    # their disk path. If the user later moved their templates
    # folder, their old settings data wouldn't deserialize
    # because the module name would no longer match up.  So we
    # are converting to just plain data types (hash of arrays.)
    def self.serialize_settings_hash(settings)
      bridge = Thread.current[:sandbox_bridge]
      out = {}
      settings.each_pair do |key, dat|
        password = dat.password
        pass_crypt = password.nil? ? nil : bridge.encrypt(password)
        out[key] = [dat.login, pass_crypt]
      end
      out
    end

    # Convert a hash of arrays, to a hash of SettingsData,
    # and decrypt the password along the way.
    def self.deserialize_settings_hash(input)
      bridge = Thread.current[:sandbox_bridge]
      settings = {}
      input.each_pair do |key, dat|
        login, pass_crypt = *input[key]
        password = pass_crypt.nil? ? nil : bridge.decrypt(pass_crypt)
        settings[key] = SettingsData.new(login, password)
      end
      settings
    end

    def self.convert_legacy_pshelter_conn_settings(dat)
      settings = {}
      records = dat.split("\n")
      records.each do |rec_str|
        rec = Hash[ *rec_str.split("\t") ] rescue {}
        next if rec.empty?
        key = rec['settingsName'].to_s
        next if key.empty?
        login, pass_plain = rec['username'].to_s, rec['password'].to_s
        settings[key] = SettingsData.new(login, pass_plain)
      end
      settings
    end
  end

  def initialize(pm_api_bridge)
#dbgprint "PShelterConnectionSettings.initialize()"
    @bridge = pm_api_bridge
    @prev_selected_settings_name = nil
    @settings = {}
  end

  def create_controls(parent_dlg)
    @ui = PShelterConnectionSettingsUI.new(@bridge)
    @ui.create_controls(parent_dlg)

    @ui.setting_name_combo.on_edit_change { handle_rename_selected }
    @ui.setting_name_combo.on_sel_change { handle_sel_change }
    @ui.setting_new_btn.on_click { handle_new_button }
    @ui.setting_delete_btn.on_click { handle_delete_button }
  end

  def layout_controls(container)
    @ui.layout_controls(container)
  end

  def destroy_controls
    @ui = nil
  end

  def save_state(serializer)
    return unless @ui
    cur_selected_name = save_current_values_to_settings
    self.class.store_settings_data(serializer, @settings)
    serializer.store(DLG_SETTINGS_KEY, :selected_item, cur_selected_name)
  end

  def restore_state(serializer)
    @settings = self.class.fetch_settings_data(serializer)
    load_combo_from_settings
    @prev_selected_settings_name = serializer.fetch(DLG_SETTINGS_KEY, :selected_item)
    if @prev_selected_settings_name
      @ui.setting_name_combo.set_selected_item(@prev_selected_settings_name)
    end

    # if we have items in the settings combo but none ended up being selected,
    # just select the 1st one
    if @ui.setting_name_combo.get_selected_item.empty?  &&  @ui.setting_name_combo.num_items > 0
      @ui.setting_name_combo.set_selected_item( @ui.setting_name_combo.get_item_at(0) )
    end

    @prev_selected_settings_name = @ui.setting_name_combo.get_selected_item
    @prev_selected_settings_name = nil if @prev_selected_settings_name.empty?

    load_current_values_from_settings
  end

  def periodic_timer_callback
  end

  protected

  def load_combo_from_settings
    @ui.setting_name_combo.reset_content( @settings.keys )
  end

  def save_current_values_to_settings(params={:name=>nil, :replace=>true})
    cur_name = params[:name]
    cur_name = @ui.setting_name_combo.get_selected_item_text.to_s unless cur_name
    if cur_name.to_s.empty?
      return "" unless current_values_worth_saving?
      cur_name = find_non_colliding_name("Untitled")
    else
      cur_name = find_non_colliding_name(cur_name) unless params[:replace]
    end
    @settings[cur_name] = SettingsData.new(@ui.login_edit.get_text, @ui.password_edit.get_text)
    cur_name
  end

  def load_current_values_from_settings
    cur_name = @ui.setting_name_combo.get_selected_item_text.to_s
    data = @settings[cur_name]
    if data
      @ui.login_edit.set_text data.login
      @ui.password_edit.set_text data.password
    end
  end

  def current_values_worth_saving?
    # i guess, if they've filled in any field, save it
    ! ( @ui.setting_name_combo.get_selected_item_text.to_s.empty?  &&
        @ui.login_edit.get_text.empty?  &&
        @ui.password_edit.get_text.empty? )
  end

  def find_non_colliding_name(want_name)
    i = 1  # first rename attempt will be "blah blah 2"
    new_name = want_name
    while @ui.setting_name_combo.has_item? new_name
      i += 1
      new_name = "#{want_name} #{i}"
    end
    new_name
  end

  def rename_in_settings(old_name, new_name)
    data = @settings[old_name]
    @settings.delete old_name
    @settings[new_name] = data
  end

  def delete_in_settings(name)
    @settings.delete name
  end

  def handle_rename_selected
    had_prev = ! @prev_selected_settings_name.nil?
    cur_name = @ui.setting_name_combo.get_text.to_s
    if cur_name != @prev_selected_settings_name
      if had_prev
        @ui.setting_name_combo.remove_item @prev_selected_settings_name
      end

      return "" if cur_name.strip.empty? && !current_values_worth_saving?
      cur_name = "Untitled" if cur_name.strip.empty?
      new_name = find_non_colliding_name(cur_name)

      if had_prev
        rename_in_settings(@prev_selected_settings_name, new_name)
      else
        saved_name = save_current_values_to_settings(:name=>new_name, :replace=>true)
        return "" unless !saved_name.empty?
      end
      @ui.setting_name_combo.add_item new_name
      @prev_selected_settings_name = new_name
      cur_name = new_name
    end
    cur_name
  end

  def save_or_rename_current_settings
    worth_saving = current_values_worth_saving?
    if @prev_selected_settings_name.nil?
    #    dbgprint "save_or_rename: prev was nil (saving if worth it)"
      if worth_saving
    #      dbgprint "save_or_rename: current worth saving"
        name = save_current_values_to_settings(:replace=>false)
        @ui.setting_name_combo.add_item(name) unless @ui.setting_name_combo.has_item? name
      end
    else
    #    dbgprint "save_or_rename: prev NOT nil (renaming)"
      new_name = handle_rename_selected
      if worth_saving
    #      dbgprint "save_or_rename: current worth saving (after rename)"
        save_current_values_to_settings(:name=>new_name, :replace=>true)
      end
    end
  end

  def handle_sel_change
    # NOTE: We rely fully on the prev. selected name here, because the
    # current selected name has already changed.
    if @prev_selected_settings_name
      save_current_values_to_settings(:name=>@prev_selected_settings_name, :replace=>true)
    end
    load_current_values_from_settings
    @prev_selected_settings_name = @ui.setting_name_combo.get_selected_item_text
  end

  def clear_settings
    @ui.setting_name_combo.set_text ""
    @ui.login_edit.set_text ""
    @ui.password_edit.set_text ""
  end

  def handle_new_button
    save_or_rename_current_settings
    @prev_selected_settings_name = nil
    clear_settings
  end

  def handle_delete_button
    cur_name = @ui.setting_name_combo.get_selected_item_text
    @ui.setting_name_combo.remove_item(cur_name) if @ui.setting_name_combo.has_item? cur_name
    delete_in_settings(cur_name)
    @prev_selected_settings_name = nil
    if @ui.setting_name_combo.num_items > 0
      @ui.setting_name_combo.set_selected_item( @ui.setting_name_combo.get_item_at(0) )
      handle_sel_change
    else
      clear_settings
    end
  end
end

module PShelterLogonHelper

  def ensure_open_ps(spec)
    login, passwd = spec.photoshelter_login, spec.photoshelter_password
    if @ps
      if login != @ps_login
        # hmm.. we shouldn't get here.
        # spec.upload_queue_key should be unique such that
        # a given PShelterUploadProtocol instance will only
        # get invoked to upload files to a given account.
        # We'll issue a warning and switch accounts...
        dbglog "WARNING: PShelterUploadProtocol: unexpected account change"
        @ps.auth_logout
        @ps = nil
        @ps_login = nil
      end
    end

    if @ps.nil?
      @ps = PhotoShelter::Connection.new(@bridge, login, passwd)
      @ps.auth_login
      @ps_login = login
    end

    @ps
  end

  def ensure_login(spec)
    @ps.auth_login unless @ps.logged_in?
    org = spec.photoshelter_organization
    if org.empty?
      @ps.org_logout unless @ps.active_org.nil?
    else
      @ps.org_login(org) unless @ps.active_org && @ps.active_org.name == org
    end
  end

end

##############################################################################
## Uploader template


class PShelterCreateCollectionDialog < Dlg::DynModalChildDialog

  include PM::Dlg
  include CreateControlHelper
  include PShelterLogonHelper

  VISIBILITY_EVERYONE = "Everyone"
  VISIBILITY_SOME = "Those with permission"
  VISIBILITY_NONE = "No one but me"

  def initialize(api_bridge, spec, pstree, parent_id, is_collection, is_listed, dialog_end_callback)
#dbgprint "PShelterCreateCollectionDialog.initialize()"
    @bridge = api_bridge
    @spec = spec
    @parent_id = parent_id
    @is_collection = is_collection
    @is_listed = is_listed
    @pstree = pstree
    @dialog_end_callback = dialog_end_callback
    @ps = nil
    @ps_login = nil
    @created_new_collection_id = false
    @new_collection_name = ""
    super()
  end

  def init_dialog
    # this will be called by c++ after DoModal()
    # calls InitDialog.
    dlg = self

  #TODO add back the key below when the dialog layout is finally complete so it gets saved for the user

    dlg.set_window_position_key("PhotoShelterCreateCollectionDialogACDC")
    dlg.set_window_position(50, 100, 400, 180)
    if @is_collection
      title = "Create New Collection"
    else
      title = "Create New Gallery"
    end
    dlg.set_window_title(title)

    parent_dlg = dlg
 #   create_control(:descrip_static,         Static,         parent_dlg, :label=>"Create New:", :align=>"left")

#    create_control(:create_gallery,        RadioButton,    dlg, :label=>"Gallery", :checked=>true)
#    create_control(:create_collection,            RadioButton,    dlg, :label=>"Collection")
#    RadioButton.set_exclusion_group(@create_gallery, @create_collection)

    create_control(:new_collection_static,          Static,         parent_dlg, :label=>"Name:", :align=>"left")
    create_control(:new_collection_edit,            EditControl,    parent_dlg, :value=>"", :persist=>false)
    create_control(:inherit_check,                  CheckBox,       parent_dlg, :label=>"Inherit Visibility & Access Permissions", :align=>"left", :checked=>true)
    create_control(:visibility_text,                Static,         parent_dlg, :label=>"Who can see this?", :align=>"left")
    create_control(:visibility_options,             ComboBox,       parent_dlg, :items=>[VISIBILITY_EVERYONE,VISIBILITY_SOME,VISIBILITY_NONE], :selected=>VISIBILITY_EVERYONE, :sorted=>false, :persist=>true)
    create_control(:create_button,                  Button,         parent_dlg, :label=>"Create", :default=>true)
    create_control(:cancel_button,                  Button,         parent_dlg, :label=>"Cancel")

    @create_button.on_click { on_create_collection }
    @cancel_button.on_click { closebox_clicked }
    @inherit_check.on_click {toggle_permissions}

    layout_controls
    instantiate_controls
    update_collection_gallery_creation_controls
    show(true)
  end

  def destroy_dialog!
    super
    (@dialog_end_callback.call(@created_new_collection_id, @new_collection_name) if @dialog_end_callback) rescue nil
  end

  def layout_controls
    sh = 20
    eh = 24
    bh = 28
    dlg = self
    client_width, client_height = dlg.get_clientrect_size
  #    dbgprint "PSCAD: clientrect: #{client_width}, #{client_height}"
    c = LayoutContainer.new(0, 0, client_width, client_height)
    c.inset(16, 10, -16, -10)
    c.pad_down(4).mark_base

    w1 = 250
    c << @new_collection_static.layout(0, c.base+3, 45, sh)
    c << @new_collection_edit.layout(c.prev_right+10, c.base, 316, eh)

    c.pad_down(14).mark_base
    c << @inherit_check.layout(0, c.base, w1, sh)

    c.pad_down(14).mark_base
    c << @visibility_text.layout(0, c.base+3, 110, sh)
      c << @visibility_options.layout(c.prev_right, c.base, 200, sh)

    bw = 80
    c << @cancel_button.layout(-(bw*2+10), -bh, bw, bh)
      c << @create_button.layout(-bw, -bh, bw, bh)
  end

  protected

  def update_collection_gallery_creation_controls
    @visibility_options.set_selected_item(VISIBILITY_NONE)
    @visibility_options.enable( true )
    @inherit_check.set_check false
    if @parent_id != ""
      parent_permission = @pstree.get_item_permission(@parent_id)
      @inherit_check.enable( true )
    else
      @inherit_check.enable( false )
    end

    if @inherit_check.checked?
      @visibility_options.enable( false )
    else
      @visibility_options.enable( true )
    end
  end

  def toggle_permissions
    if @inherit_check.checked?
      @visibility_options.enable( false )
      parent_permission = @pstree.get_item_permission(@parent_id)
      case parent_permission
      when "everyone"
        @visibility_options.set_selected_item(VISIBILITY_EVERYONE)
      when "permission"
        @visibility_options.set_selected_item(VISIBILITY_SOME)
      when "private"
        @visibility_options.set_selected_item(VISIBILITY_NONE)
      else
        @visibility_options.set_selected_item(VISIBILITY_NONE)
      end
    else
      @visibility_options.enable( true )
      @visibility_options.set_selected_item(VISIBILITY_NONE)
    end
  end

  def on_create_collection
    inherit = "t"
    visibility = "private"
    f_list = "f"

    name = @new_collection_edit.get_text.strip
    if name.empty?
      Dlg::MessageBox.ok("Please enter a name.", Dlg::MessageBox::MB_ICONEXCLAMATION)
      return
    end

#    parent_collection_path = @parent_collection_combo.get_selected_item
    if @parent_id != ""
      if @inherit_check.checked?
        inherit = "t"
      else
        inherit = "f"
        visibility = @visibility_options.get_selected_item
      end
    else
      inherit = "f"
      visibility = @visibility_options.get_selected_item
    end

    begin
      ensure_open_ps(@spec)
      ensure_login(@spec)

      case visibility
      when VISIBILITY_EVERYONE
        vis = "everyone"
      when VISIBILITY_SOME
        vis = "permission"
      when VISIBILITY_NONE
        vis = "private"
      else
        vis = "private"
      end

      type = "gallery"
      if @is_collection
        type = "collection"
      end

      if @is_listed && @parent_id == "" && !@is_collection
        f_list = "t"
      else
        f_list = "f"
      end
      @created_new_collection_id = @ps.create_collection_gallery(@parent_id, type, name, f_list, inherit, vis)

      @pstree = @ps.collection_query

    rescue StandardError => ex
   #   dbgprint(ex.message)
      Dlg::MessageBox.ok("Failed to create collection '#{name}' at PhotoShelter.\nError: #{ex.message}", Dlg::MessageBox::MB_ICONEXCLAMATION)
    ensure
      @ps.auth_logout if @ps
      @ps = nil
      end_dialog(IDOK)
    end
  end

end

class PShelterFileUploaderUI

  include PM::Dlg
  include AutoAccessor
  include CreateControlHelper
  include ImageProcessingControlsCreation
  include ImageProcessingControlsLayout
  include OperationsControlsCreation
  include OperationsControlsLayout

  SOURCE_RAW_LABEL = "Use the RAW"
  SOURCE_JPEG_LABEL = "Use the JPEG"

  SEND_RAW_JPEG_LABEL = "Send both RAW & JPEG files"
  SEND_JPEG_ONLY_LABEL = "Send JPEG files only"
  SEND_RAW_ONLY_LABEL = "Send RAW files only"

  DEST_EXISTS_UPLOAD_ANYWAY_LABEL = "Upload file anyway (files of same name can safely coexist)"
  DEST_EXISTS_RENAME_LABEL = "Rename file before uploading"
  DEST_EXISTS_SKIP_LABEL = "Skip file (do not upload)"

  def initialize(pm_api_bridge)
#dbgprint "PShelterFileUploaderUI.initialize()"
    @bridge = pm_api_bridge
  end

  def create_controls(parent_dlg)
    dlg = parent_dlg

    create_control(:dest_account_group_box,     GroupBox,       dlg, :label=>"Destination PhotoShelter Account:")
    create_control(:dest_account_static,        Static,         dlg, :label=>"Account:", :align=>"right")
    create_control(:dest_account_combo,         ComboBox,       dlg, :sorted=>true, :persist=>false)

    create_control(:dest_org_static,            Static,         dlg, :label=>"Organization:", :align=>"right")
    create_control(:dest_org_combo,             ComboBox,       dlg, :sorted=>false, :persist=>false)
    create_control(:dest_photog_static,         Static,         dlg, :label=>"Photographer Uploading As:", :align=>"right")
    create_control(:dest_photog_combo,          ComboBox,       dlg, :sorted=>false, :persist=>false)

    create_control(:browser_group_box,     GroupBox,       dlg, :label=>"Upload Preferences:")
    create_control(:browser_tree_text,            Static,         dlg, :label=>"View:", :align=>"left")
    create_control(:browser_tree_website,        RadioButton,    dlg, :label=>"Listed On Website", :checked=>true)
    create_control(:browser_tree_non_website,            RadioButton,    dlg, :label=>"Unlisted On Website")
    RadioButton.set_exclusion_group(@browser_tree_website, @browser_tree_non_website)
    create_control(:browser_refresh,   Button,         dlg, :label=>"Refresh")
    create_control(:browser_create_collection_button,   Button,         dlg, :label=>"New Collection...")
    create_control(:browser_create_gallery_button,      Button,         dlg, :label=>"New Gallery...")

    create_control(:browser_columnbrowser,              PShelterColumnBrowser, dlg)
    create_control(:browser_pubsearch_check,       CheckBox,       dlg, :label=>"Make Images Publicly Searchable")
    create_control(:browser_file_exists_static,    Static,         dlg, :label=>"If file already exists on server:", :align=>"right")
    create_control(:browser_file_exists_combo,     ComboBox,       dlg, :items=>[DEST_EXISTS_UPLOAD_ANYWAY_LABEL,DEST_EXISTS_RENAME_LABEL,DEST_EXISTS_SKIP_LABEL], :selected=>DEST_EXISTS_UPLOAD_ANYWAY_LABEL, :sorted=>false, :persist=>true)

    create_control(:transmit_group_box,         GroupBox,       dlg, :label=>"Transmit:")
    create_control(:send_original_radio,        RadioButton,    dlg, :label=>"Original Photos", :checked=>true)
    create_control(:send_jpeg_radio,            RadioButton,    dlg, :label=>"Saved as JPEG")
    RadioButton.set_exclusion_group(@send_original_radio, @send_jpeg_radio)

    create_control(:send_raw_jpeg_static,       Static,         dlg, :label=>"RAW+JPEG:", :align=>"right")
    create_control(:send_raw_jpeg_combo,        ComboBox,       dlg, :items=>[SEND_RAW_JPEG_LABEL,SEND_JPEG_ONLY_LABEL,SEND_RAW_ONLY_LABEL], :selected=>SEND_RAW_JPEG_LABEL, :sorted=>false)
    #------------------------------------------
    create_jpeg_controls(dlg)
    #------------------------------------------
    create_image_processing_controls(dlg)
    #------------------------------------------
    create_operations_controls(dlg)
    #------------------------------------------
  end

  STATIC_TEXT_HEIGHT = 20
  EDIT_FIELD_HEIGHT = 24
  COLOR_BUTTON_HEIGHT = 24
  RIGHT_PAD = 5
  def layout_controls(container)
    sh = STATIC_TEXT_HEIGHT
    eh = EDIT_FIELD_HEIGHT
    ch = COLOR_BUTTON_HEIGHT
    rp = RIGHT_PAD

    container.inset(15, 5, -15, -5)
    container.layout_with_contents(@dest_account_group_box, 0, 0, -1, -1) do |c|
      c.set_prev_right_pad(rp).inset(10,25,-10,-5).mark_base

      c.layout_subgroup(0, c.base, "45%-5", -1) do |cl|
        cl.set_prev_right_pad(rp)
        cl << @dest_account_static.layout(0, cl.base+3, 120, sh)
        cl << @dest_account_combo.layout(cl.prev_right, cl.base, -1, eh)
        cl.pad_down(5).mark_base.size_to_base
      end

      c.layout_subgroup("45%+5", c.base, -1, -1) do |cr|
        cr.set_prev_right_pad(rp)
        cr << @dest_org_static.layout(0, cr.base+3, 180, sh)
        cr << @dest_org_combo.layout(cr.prev_right, cr.base, -1, eh)
        cr.pad_down(5).mark_base
        cr << @dest_photog_static.layout(0, cr.base+3, 180, sh)
        cr << @dest_photog_combo.layout(cr.prev_right, cr.base, -1, eh)
        cr.pad_down(5).mark_base.size_to_base
      end

      c.pad_down(5).mark_base.size_to_base
    end

    container.pad_down(5).mark_base

    container.layout_with_contents(@browser_group_box, 0, container.base, -1, -1) do |c|
      c.set_prev_right_pad(rp).inset(10,25,-10,-5).mark_base

      c << @browser_tree_text.layout(0, c.base+3, 50, sh)
      w1 = 150
      c << @browser_tree_website.layout(c.prev_right, c.base, w1, sh)
      c << @browser_tree_non_website.layout(c.prev_right, c.base, w1, sh)
      c << @browser_refresh.layout("100%-120", c.base, 120, sh)
      c.pad_down(10).mark_base
      c << @browser_create_collection_button.layout(0, c.base, 160, 24)
      c << @browser_create_gallery_button.layout(c.prev_right, c.base, 160, 24)
      c.pad_down(14).mark_base

      c << @browser_columnbrowser.layout(5, c.base, -5, 200)
      c.pad_down(8).mark_base

      c << @browser_pubsearch_check.layout(0, c.base, 250, eh)
        c << @browser_file_exists_static.layout(c.prev_right, c.base+3, 200, sh)
          c << @browser_file_exists_combo.layout(c.prev_right, c.base, -1, eh)

      c.pad_down(5).mark_base.size_to_base
    end

    container.pad_down(5).mark_base

    container.layout_with_contents(@transmit_group_box, 0, container.base, "50%-5", -1) do |xmit_container|
      c = xmit_container
      c.set_prev_right_pad(rp).inset(10,25,-10,-5).mark_base

      c << @send_original_radio.layout(0, c.base, 130, eh)
        c << @send_raw_jpeg_static.layout(c.prev_right, c.base+3, 80, sh)
      save_right = c.prev_right
          c << @send_raw_jpeg_combo.layout(c.prev_right, c.base, -1, sh)
      c.pad_down(5).mark_base
      c << @send_jpeg_radio.layout(0, c.base, 130, eh)
      c.pad_down(5).mark_base

      layout_jpeg_controls(c, eh, sh)

      c.layout_with_contents(@imgproc_group_box, 0, c.base, -1, -1) do |c|
        c.set_prev_right_pad(rp).inset(10,25,-10,-5).mark_base

        w1, w2 = 70, 182
        w1w = (w2 - w1)
        layout_image_processing_controls(c, eh, sh, w1, w2, w1w)
      end
      c = xmit_container

      c.pad_down(5).mark_base
      c.mark_base.size_to_base
    end

    layout_operations_controls(container, eh, sh, rp)

    container.pad_down(20).mark_base
  end

  def have_source_raw_jpeg_controls?
    defined?(@source_raw_jpeg_static) && defined?(@source_raw_jpeg_combo)
  end

  def raw_jpeg_render_source
    src = "JPEG"
    if have_source_raw_jpeg_controls?
      src = "RAW" if @source_raw_jpeg_combo.get_selected_item == SOURCE_RAW_LABEL
    end
    src
  end

end


class PShelterColumnBrowser < Dlg::ColumnBrowser

  @cached_items = {}
  @cached_path_cache = {}
  @cached_pstree = {}
  @cached_full_selpath = []
  @cache_is_set = false

  ROOT = "/"

  def post_init

    @items = {}
    @path_cache = {}
    @full_selpath = []

    @gallerycolor = 0x000000
    @collectioncolor = 0x333333
    @addcolor = 0x33af33
    @last_selected_row = 0
    @last_selected_col = 0

    self.on_query_num_rows_in_column do |col, full_selpath|
      begin
        query_num_rows_in_column(col, full_selpath)
      rescue Exception => ex
        dbglog("PShelterColumnBrowser:on_query_num_rows_in_column exception: #{ex.inspect}\n#{ex.backtrace_to_s}")
        raise
      end
    end

    self.on_will_display_cell_at_row_col do |row, col, full_selpath|
      begin
        will_display_cell_at_row_col(row, col, full_selpath)
      rescue Exception => ex
        dbglog("PShelterColumnBrowser:on_will_display_cell_at_row_col exception: #{ex.inspect}\n#{ex.backtrace_to_s}")
        raise
      end
    end

    self.on_click do |row, col|
      begin
        selected_path = get_selected_path
        node = @items[col][row]
        @last_selected_col = col
        @last_selected_row = row
        @pstree.update_selected(node)
        if(node.type == "collection")
          nodes = @pstree.get_cached_children(node)
          col+=1
          setup_column(col,nodes,selected_path)

          num_items = query_num_rows_in_column(col, selected_path)
          row = 0
          while row < num_items  do
            will_display_cell_at_row_col(row, col, selected_path)
             row +=1
          end
          reload_column(col)
        end
      rescue Exception => ex
 #       dbglog("PShelterColumnBrowser:on_query_num_rows_in_column exception: #{ex.inspect}\n#{ex.backtrace_to_s}")
        raise
      end
    end
  end

  def set_tree(tree,listed_on_website)
    @pstree = tree

    if @cache_is_set == true && @cached_full_selpath != {}
      @pstree.set_cache(@cached_pstree)
      @items = @cached_items
      @path_cache = @cached_path_cache

      @items.each do |col, value|
        tmp_node_array = []
        value.each do |row, node|
          tmp_node_array[row] = node
        end
        setup_column(col, tmp_node_array, @cached_full_selpath)
      end

      load_column_zero

      col = 0
      @cached_full_selpath.each do |row|
        select_row_in_column(row, col)
        col = col + 1
      end

      select_row_in_column(get_last_selected_row, get_last_selected_col)
      if @items[get_last_selected_col] != nil
        @pstree.update_selected(@items[get_last_selected_col][get_last_selected_row])
      end
    else
      if listed_on_website
        nodes = @pstree.top_level_nodes(true)
      else
        nodes = @pstree.top_level_nodes(false)
      end
      col = 0
      setup_column(col,nodes,[])
      load_column_zero
    end
  end

  def reset_tree(listed_on_website)
    if listed_on_website
      nodes = @pstree.top_level_nodes(true)
    else
      nodes = @pstree.top_level_nodes(false)
    end
    @path_cache = {}
    @items = {}
    col = 0
    setup_column(col,nodes,[])
    load_column_zero
  end

  def update_column(col,is_listed, created_new_collection_id)
    #col will never be 0 in here!
    selected_path = get_selected_path
    @items[col] = {}
    row = selected_path[col-1]
    node = @items[col-1][row]

    if(node.type == "collection")
      nodes = @pstree.get_children(node)
      setup_column(col,nodes,selected_path)
    end

    num_items = query_num_rows_in_column(col, selected_path)
    row = 0
    while row < num_items  do
      will_display_cell_at_row_col(row, col, selected_path)
       row +=1
    end
    reload_column(col)

    new_item_row = 0
    row = 0
    nodes.each do |node|
      if node.id == created_new_collection_id
        new_item_row = row
      end
      row = row+1
    end
    #select the new item here
    set_last_selected_col(col)
    set_last_selected_row(new_item_row)
    select_row_in_column(new_item_row, col)
    @pstree.update_selected(@items[col][new_item_row])

  end

  def get_items
    @items
  end

  def set_cached_items(items)
    @cached_items = items
  end

  def get_full_selpath
    @full_selpath
  end

  def set_cached_full_selpath(full_selpath)
    @cached_full_selpath = full_selpath
  end

  def get_pstree_cache
    if @pstree
      @pstree.get_cache
    else
      nil
    end
  end

  def set_cached_pstree(cache)
    @cached_pstree = cache
    @cache_is_set = true
  end

  def get_last_selected_col
    @last_selected_col
  end

  def get_last_selected_row
    @last_selected_row
  end

  def set_last_selected_col(col)
    @last_selected_col = col
  end

  def set_last_selected_row(row)
    @last_selected_row = row
  end

  def get_path_cache
    @path_cache
  end

  def set_cached_path_cache(path_cache)
    @cached_path_cache = path_cache
  end

  def public_reload_column(col)
    reload_column(col)
  end

  def query_num_rows_in_column(col, full_selpath)
    if col.zero?
      if @path_cache.empty?
        0
      else
        @path_cache[ROOT].size
      end
    else
      selpath = limit_selpath_to_col(full_selpath, col)
      path = build_path_from_selpath(selpath)
      cached_items(path).size
    end
  end

  def will_display_cell_at_row_col(row, col, full_selpath)
    node = {}
    if @items.key?(col)
      if @items[col].key?(row)
      node = @items[col][row]
      end
    end
    selpath = limit_selpath_to_col(full_selpath, col)
    path = build_path_from_selpath(selpath)
    dat = generate_cell_data(node)
    dat
  end

  def reset_cache
    @cache_is_set = false
    @path_cache = {}
    @full_selpath = []
    @items = {}
  end

  def set_ui_theme(style)
    if style == "DarkUI"
      @gallerycolor = 0xbbbbbb
      @collectioncolor = 0xffffff
      @addcolor = 0x33af33
    end
  end

  protected

  def setup_column(col,nodes,full_selpath)
    already_has_add_collection = false

    tmp_path_array = []
    nodes.each do |node|
      begin
        tmp_path_array << node.name
      rescue Exception => ex
        raise
      end
    end

    if col == 0
      @path_cache[ROOT] = tmp_path_array
    else
      selpath = limit_selpath_to_col(full_selpath, col)
      path = build_path_from_selpath(selpath)
      @path_cache[path] = tmp_path_array
    end
    @items[col] = {}
    row = 0
    nodes.each do |node|
      begin
        setup_cell(row, col, full_selpath, node)
        row+=1
      rescue Exception => ex
        dbglog("PShelterColumnBrowser:setup_column exception: #{ex.inspect}\n#{ex.backtrace_to_s}")
        raise
      end
    end
  end

  def setup_cell(row, col, full_selpath, node)
     @full_selpath = full_selpath
     if !@items.key?(col)
       @items[col] = {}
     end
     @items[col][row] = node
     selpath = limit_selpath_to_col(full_selpath, col)
     path = build_path_from_selpath(selpath)
     dat = generate_cell_data(node)
     dat
   end

  def limit_selpath_to_col(selpath, col)
    selpath[0...col]  # will be [] for col=0
  end

  def build_path_from_selpath(selpath)
    path = ROOT
    selpath.each do |row|
      entries = cached_items(path)
      entry = entries[row] || "ERROR"
      path = path + entry
    end
    path = path + "/"
    path
  end

  def cached_items(path)
    unless (entries = @path_cache[path])
      entries = []
      end
      entries
  end

  def generate_cell_data(node)
    if node == {}
      return {}
    else
      if node.type == "collection"
        {
          "text" => node.htmlname,
          "is_leaf" => false,
          "is_bold" => true,
          "text_color" => @collectioncolor
        }
      else
        if node.type == "gallery"
          {
            "text" => node.htmlname,
            "is_leaf" => true,
            "is_bold" => false,
            "text_color" => @gallerycolor
          }
        else
          {
            "text" => node.htmlname,
            "is_leaf" => true,
            "is_bold" => false,
            "text_color" => @addcolor
          }
        end
      end
    end
  end
end

class PShelterFileUploader

  # must include PM::FileUploaderTemplate so that
  # the template manager can find our class in
  # ObjectSpace
  include PM::FileUploaderTemplate
  include ImageProcessingControlsLogic
  include OperationsControlsLogic
  include RenamingControlsLogic
  include JpegSizeEstimationLogic
  include UpdateComboLogic
  include FormatBytesizeLogic

  DLG_SETTINGS_KEY = :upload_dialog  # don't worry, won't conflict with other templates

  def self.template_display_name  # template name shown in dialog list box
    TEMPLATE_DISPLAY_NAME
  end

  def self.template_description  # shown in dialog box
    "Upload images to PhotoShelter"
  end

  def self.conn_settings_class
    PShelterConnectionSettings
  end

  def initialize(pm_api_bridge, num_files, dlg_status_bridge, conn_settings_serializer)
   # dbgprint "PShelterFileUploader.initialize()"
    @bridge = pm_api_bridge
    @num_files = num_files
    @dlg_status_bridge = dlg_status_bridge
    @conn_settings_ser = conn_settings_serializer
    @last_status_txt = nil
    @data_fetch_worker = nil
    @account_parameters_dirty = false
    @refresh_col_browser = false
    @pstree = nil
    @col_zero_node_id_to_select = nil
  end

  def upload_files(global_spec, progress_dialog)
    raise "upload_files called with no @ui instantiated" unless @ui
    acct = cur_account_settings
    raise "Failed to load settings for current account. Try Edit Connections..." unless acct
    spec = build_upload_spec(acct, @ui)
    # @bridge.kickoff_photoshelter_upload(spec.__to_hash__)
    @bridge.kickoff_template_upload(spec, PShelterUploadProtocol)
  end

  def preflight_settings(global_spec)
    raise "preflight_settings called with no @ui instantiated" unless @ui

    acct = cur_account_settings
    raise "Failed to load settings for current account. Try Edit Connections..." unless acct
    raise "Some account settings appear invalid or missing. Please choose Edit Connections..." unless acct.appears_valid?

    preflight_renaming_controls
    preflight_operations_controls
    preflight_jpeg_controls

    spec = build_upload_spec(acct, @ui)
    # TODO: ???
  end

  def create_controls(parent_dlg)
    @ui = PShelterFileUploaderUI.new(@bridge)
    @ui.create_controls(parent_dlg)

    @ui.browser_columnbrowser.set_ui_theme(@bridge.get_ui_theme())

    @ui.browser_tree_website.on_click{
      @ui.browser_columnbrowser.set_last_selected_col(-1)
      @ui.browser_columnbrowser.set_last_selected_row(-1)
      @ui.browser_columnbrowser.reset_tree(true)
      @ui.browser_columnbrowser.public_reload_column(0)
    }

    @ui.browser_tree_non_website.on_click{
      @ui.browser_columnbrowser.set_last_selected_col(-1)
      @ui.browser_columnbrowser.set_last_selected_row(-1)
      @ui.browser_columnbrowser.reset_tree(false)
      @ui.browser_columnbrowser.public_reload_column(0)
    }

    @ui.browser_refresh.on_click{
      @ui.browser_columnbrowser.reset_cache
      @data_fetch_worker.clear_pstree
      account_parameters_changed
    }

    @ui.browser_create_collection_button.on_click{
       begin
         selected_path = @ui.browser_columnbrowser.get_selected_path
         row = @ui.browser_columnbrowser.get_last_selected_row
         col = @ui.browser_columnbrowser.get_last_selected_col
         items = @ui.browser_columnbrowser.get_items
         selected_type = "collection"
         if row == -1 || col == -1
           parent_id = ""
         else
           parent_node = items[col][row]
           if parent_node.type == "gallery"
             selected_type = "gallery"
             if col == 0
               parent_id = ""
             else
               parent_id = parent_node.parent_id
               col = col-1
             end
           else
             parent_id = parent_node.id
           end
         end
         run_create_collection_dialog(parent_id, col, selected_path, true, selected_type)
       rescue Exception => ex
           dbglog("PShelterColumnBrowser:@ui.browser_create_collection_button.on_click exception: #{ex.inspect}\n#{ex.backtrace_to_s}")
         raise
       end
    }
    @ui.browser_create_gallery_button.on_click {
      begin
        selected_path = @ui.browser_columnbrowser.get_selected_path
        row = @ui.browser_columnbrowser.get_last_selected_row
        col = @ui.browser_columnbrowser.get_last_selected_col
        items = @ui.browser_columnbrowser.get_items
        selected_type = "collection"
        if row == -1 && col == -1
          parent_id = ""
        else
          parent_node = items[col][row]
          if parent_node.type == "gallery"
            selected_type = "gallery"
            if col == 0
              parent_id = ""
            else
              parent_id = parent_node.parent_id
              col = col-1
            end
          else
            parent_id = parent_node.id
          end
        end
        run_create_collection_dialog(parent_id, col, selected_path, false, selected_type)
      rescue Exception => ex
         dbglog("PShelterColumnBrowser:@ui.browser_create_gallery_button.on_click exception: #{ex.inspect}\n#{ex.backtrace_to_s}")
       raise
     end
  }

    @ui.send_original_radio.on_click {adjust_controls}
    @ui.send_jpeg_radio.on_click {adjust_controls}

    @ui.dest_account_combo.on_sel_change {
      @refresh_col_browser = true
      account_parameters_changed
    }
    @ui.dest_org_combo.on_sel_change {
      @refresh_col_browser = true
      account_parameters_changed
    }

    add_jpeg_controls_event_hooks
    add_operations_controls_event_hooks
    add_renaming_controls_event_hooks
    add_image_processing_controls_event_hooks
    set_seqn_static_to_current_seqn

    @last_status_txt = nil
    @data_fetch_worker = PShelterAccountQueryWorker.new(@bridge)
  end

  def layout_controls(container)
    @ui.layout_controls(container)
  end

  def destroy_controls
    @data_fetch_worker.close if @data_fetch_worker
    @data_fetch_worker = nil
    @ui = nil
  end

  def save_state(serializer)
    return unless @ui
    serializer.store(DLG_SETTINGS_KEY, :selected_account, @ui.dest_account_combo.get_selected_item)
    serializer.store(DLG_SETTINGS_KEY, :selected_org,     @ui.dest_org_combo.get_selected_item)
    serializer.store(DLG_SETTINGS_KEY, :selected_photog,  @ui.dest_photog_combo.get_selected_item)

    serializer.store(DLG_SETTINGS_KEY, :selected_listed,   @ui.browser_tree_website.checked?)
    serializer.store(DLG_SETTINGS_KEY, :cached_items,   @ui.browser_columnbrowser.get_items)
    serializer.store(DLG_SETTINGS_KEY, :cached_path,   @ui.browser_columnbrowser.get_path_cache)
    serializer.store(DLG_SETTINGS_KEY, :cached_tree,   @ui.browser_columnbrowser.get_pstree_cache)
    serializer.store(DLG_SETTINGS_KEY, :cached_full_selpath,   @ui.browser_columnbrowser.get_full_selpath)

    serializer.store(DLG_SETTINGS_KEY, :cached_selected_row,   @ui.browser_columnbrowser.get_last_selected_row)
    serializer.store(DLG_SETTINGS_KEY, :cached_selected_col,   @ui.browser_columnbrowser.get_last_selected_col)
  end

  def restore_state(serializer)
    data = fetch_conn_settings_data
    @ui.dest_account_combo.reset_content( data.keys )

    prev_selected_account = serializer.fetch(DLG_SETTINGS_KEY, :selected_account)
    @ui.dest_account_combo.set_selected_item(prev_selected_account) if prev_selected_account

    # if we have items in the accounts combo but none ended up being selected,
    # just select the 1st one
    if @ui.dest_account_combo.get_selected_item.empty?  &&  @ui.dest_account_combo.num_items > 0
      @ui.dest_account_combo.set_selected_item( @ui.dest_account_combo.get_item_at(0) )
    end

    # We don't persist all the data for these combo boxes, so initially
    # we just make the remembered selected item the only item in the
    # combo, and select it.  Later when the background data fetch completes,
    # it will update the combo and preserve the selection if possible.
    prev_selected_collection = serializer.fetch(DLG_SETTINGS_KEY, :selected_group)
    prev_selected_org = serializer.fetch(DLG_SETTINGS_KEY, :selected_org)
    prev_selected_photog = serializer.fetch(DLG_SETTINGS_KEY, :selected_photog)

#    update_combo(:browser_collection_combo, [prev_selected_collection]) unless prev_selected_collection.to_s.empty?
    update_combo(:dest_org_combo, [prev_selected_org]) unless prev_selected_org.to_s.empty?
    update_combo(:dest_photog_combo, [prev_selected_photog]) unless prev_selected_photog.to_s.empty?

    if serializer.fetch(DLG_SETTINGS_KEY, :cached_tree) != nil
    #  @pstree = serializer.fetch(DLG_SETTINGS_KEY, :cached_tree)
      @ui.browser_columnbrowser.set_cached_pstree(serializer.fetch(DLG_SETTINGS_KEY, :cached_tree))
    end

    if serializer.fetch(DLG_SETTINGS_KEY, :cached_items)
      @ui.browser_columnbrowser.set_cached_items(serializer.fetch(DLG_SETTINGS_KEY, :cached_items))
    end

    if serializer.fetch(DLG_SETTINGS_KEY, :cached_path) != nil
      @ui.browser_columnbrowser.set_cached_path_cache(serializer.fetch(DLG_SETTINGS_KEY, :cached_path))
    end

    if serializer.fetch(DLG_SETTINGS_KEY, :cached_full_selpath) != nil
      @ui.browser_columnbrowser.set_cached_full_selpath(serializer.fetch(DLG_SETTINGS_KEY, :cached_full_selpath))
    end

    if serializer.fetch(DLG_SETTINGS_KEY, :cached_selected_row) != nil
      @ui.browser_columnbrowser.set_last_selected_row(serializer.fetch(DLG_SETTINGS_KEY, :cached_selected_row))
    end

    if serializer.fetch(DLG_SETTINGS_KEY, :cached_selected_col) != nil
      @ui.browser_columnbrowser.set_last_selected_col(serializer.fetch(DLG_SETTINGS_KEY, :cached_selected_col))
    end

    prev_listed = serializer.fetch(DLG_SETTINGS_KEY, :selected_listed)
    if prev_listed
      @ui.browser_tree_website.set_check
    else
      @ui.browser_tree_non_website.set_check
    end

    account_parameters_changed
    adjust_controls
  end

  def periodic_timer_callback
    return unless @ui
    handle_background_data_fetch
    handle_jpeg_size_estimation
  end

  def set_status_text(txt)
    if txt != @last_status_txt
      @dlg_status_bridge.set_text(txt)
      @last_status_txt = txt
    end
  end

  # Called by the framework after user has brought up the Connection Settings
  # dialog.
  def connection_settings_edited(conn_settings_serializer)
    @conn_settings_ser = conn_settings_serializer

    data = fetch_conn_settings_data
    @ui.dest_account_combo.reset_content( data.keys )
    selected_settings_name = PShelterConnectionSettings.fetch_selected_settings_name(@conn_settings_ser)
    if selected_settings_name
      @ui.dest_account_combo.set_selected_item( selected_settings_name )
    end

    # if selection didn't take, and we have items in the list, just pick the 1st one
    if @ui.dest_account_combo.get_selected_item.empty?  &&  @ui.dest_account_combo.num_items > 0
      @ui.dest_account_combo.set_selected_item( @ui.dest_account_combo.get_item_at(0) )
    end

    account_parameters_changed
    handle_background_data_fetch
  end

  def imglink_button_spec
    { :filename => "logo.tif", :bgcolor => "ffffff" }
  end

  def imglink_url
    "http://www.photoshelter.com/ref/cbits"
  end

  protected

  def  run_create_collection_dialog(parent_id, col, selected_path, is_collection, selected_type)
    dbgprint("rar")
    return unless @pstree
    if selected_type == "collection"
      col = col + 1
    end

    if @ui.browser_tree_website.checked?
      is_listed = true
    else
      is_listed = false
    end

    # these sanity checks really shouldn't be necessary, as
    # the create button is in theory disabled if they are false
    if @account_parameters_dirty
      Dlg::MessageBox.ok("Can't create collections, still awaiting required information from PhotoShelter.", Dlg::MessageBox::MB_ICONEXCLAMATION)
      return
    end
    acct = cur_account_settings
    unless acct && acct.appears_valid?
      Dlg::MessageBox.ok("Account settings appear missing or invalid. Please try Edit Connections...", Dlg::MessageBox::MB_ICONEXCLAMATION)
      return
    end
    set_status_text "Ready to create collection."

    spec = build_upload_spec(acct, @ui)

    dialog_end_callback = lambda {|created_new_collection_id, new_collection_name| handle_new_collection_created(created_new_collection_id, new_collection_name, col, is_listed)}
    cdlg = PShelterCreateCollectionDialog.new(@bridge, spec, @pstree, parent_id, is_collection, is_listed, dialog_end_callback)
    cdlg.instantiate!
    cdlg.request_deferred_modal
  end

  def handle_new_collection_created (created_new_collection_id, new_collection_name, col, is_listed)
    if created_new_collection_id != false
      if col == 0
        @ui.browser_columnbrowser.reset_cache
        @refresh_col_browser = true
        @data_fetch_worker.clear_pstree
        @col_zero_node_id_to_select = created_new_collection_id
        account_parameters_changed
      else
        @ui.browser_columnbrowser.update_column(col,is_listed,created_new_collection_id)
      end
      set_status_text "New Collection / Gallery Created."
    else
      set_status_text "Ready."
    end
  end

  def adjust_controls
    may_raw_plus_jpeg = @bridge.document_combines_raw_plus_jpeg?
    ctls = [
      @ui.send_raw_jpeg_static,
      @ui.send_raw_jpeg_combo
    ]
    ctls.each do |ctl|
      ctl.enable(may_raw_plus_jpeg)
      ctl.show(may_raw_plus_jpeg)
    end

    adjust_image_processing_controls
    adjust_operations_controls
    adjust_renaming_controls

    ctl = @ui.dest_photog_combo
    ctl.enable( ctl.num_items >= 1 )

    ctl = @ui.dest_org_combo
    ctl.enable( @data_fetch_worker && @data_fetch_worker.multi_user_access? )

    ctl = @ui.browser_pubsearch_check
    ctl.enable( @data_fetch_worker && @data_fetch_worker.can_make_publicly_searchable?, :state_while_disabled => false )

    ctl = @ui.browser_tree_website
    ctl.enable( @data_fetch_worker && @pstree )

    ctl = @ui.browser_tree_non_website
    ctl.enable( @data_fetch_worker && @pstree )

    ctl = @ui.browser_columnbrowser
    ctl.enable( @data_fetch_worker && @pstree )

    ctl = @ui.browser_refresh
    ctl.enable( @data_fetch_worker && @pstree )

    ctl = @ui.browser_create_collection_button
    ctl.enable( @data_fetch_worker && @pstree )

    ctl = @ui.browser_create_gallery_button
    ctl.enable( @data_fetch_worker && @pstree )

  end

  def build_upload_spec(acct, ui)
    spec = AutoStruct.new

    # string displayed in upload progress dialog title bar:
    spec.upload_display_name  = "photoshelter.com:#{acct.login}"
    # string used in logfile name, should have NO spaces or funky characters:
    spec.log_upload_type      = TEMPLATE_DISPLAY_NAME.tr('^A-Za-z0-9_-','')
    # account string displayed in upload log entries:
    spec.log_upload_acct      = spec.upload_display_name

    spec.num_files = @num_files

    spec.photoshelter_login        = acct.login
    spec.photoshelter_password     = acct.password

    if !@pstree.nil?
      selected_node = @pstree.get_selected
      if selected_node.type == "collection"
        spec.photoshelter_collection = selected_node.id
        spec.photoshelter_gallery = ""
      else
        if selected_node.type == "gallery"
          spec.photoshelter_collection = ""
          spec.photoshelter_gallery = selected_node.id
        else
          spec.photoshelter_collection = selected_node.parent_id
          spec.photoshelter_gallery = ""
        end
      end
    end

    org = ui.dest_org_combo.get_selected_item
    org = "" if org == PShelterAccountQueryWorker::SUBSCRIBER_ACCT_NAME
    spec.photoshelter_organization = org

    # NOTE: upload_queue_key should be unique for a given protocol,
    #       and a given upload "account".
    #       Rule of thumb: If file A requires a different
    #       login than file B, they should have different
    #       queue keys.
    #       Thus here for photoshelter, we use login/password/org,
    #       because these affect how we login to transfer the file.
    #       But we don't include the collection folder in the key,
    #       because we can upload to different collection folders
    #       on a given login.
    spec.upload_queue_key = [
      "photoshelter",
      spec.photoshelter_login,
      spec.photoshelter_password,
      spec.photoshelter_organization
    ].join("\t")

    photog = ui.dest_photog_combo.get_selected_item
    photog = "" if photog == PShelterAccountQueryWorker::PHOTOG_LEAVE_BLANK
    spec.photoshelter_photog = photog

    if @bridge.document_combines_raw_plus_jpeg?
      raw_jpeg = case ui.send_raw_jpeg_combo.get_selected_item
      when PShelterFileUploaderUI::SEND_RAW_JPEG_LABEL then "RAW+JPEG"
      when PShelterFileUploaderUI::SEND_RAW_ONLY_LABEL then "RAW"
      else                                                  "JPEG"
      end
    else
      raw_jpeg = "RAW+JPEG"
    end
    spec.combined_raw_jpeg_upload_setting = raw_jpeg

    replace_style = case ui.browser_file_exists_combo.get_selected_item
    when PShelterFileUploaderUI::DEST_EXISTS_RENAME_LABEL        then "RENAME_BEFORE_UPLOADING"
    when PShelterFileUploaderUI::DEST_EXISTS_SKIP_LABEL          then "SKIP_FILE"
    else                                                              "UPLOAD_ANYWAY"
    end
    spec.file_exists_replace_style = replace_style

    spec.make_publicly_searchable = ui.browser_pubsearch_check.checked?

    spec.upload_processing_type = ui.send_original_radio.checked? ? "originals" : "save_as_jpeg"
    spec.send_incompatible_originals_as = "JPEG"
    spec.send_wav_files = false

    build_jpeg_spec(spec, ui)
    build_image_processing_spec(spec, ui)
    build_operations_spec(spec, ui)
    build_renaming_spec(spec, ui)
    spec
  end

  def fetch_conn_settings_data
    PShelterConnectionSettings.fetch_settings_data(@conn_settings_ser)
  end

  def cur_account_settings
    acct_name = @ui.dest_account_combo.get_selected_item
    data = fetch_conn_settings_data
    settings = data ? data[acct_name] : nil
  end

  def account_parameters_changed
    @account_parameters_dirty = true
  end

  def handle_background_data_fetch
    acct = cur_account_settings
    if acct.nil?
      set_status_text("Please select an account, or choose Edit Connections...")
    elsif ! acct.appears_valid?
      set_status_text("Some account settings appear invalid or missing. Please choose Edit Connections...")
    else

      if @account_parameters_dirty
        login = acct.login
        passwd = acct.password
        org = @ui.dest_org_combo.get_selected_item
        org = nil if org.empty?
        @data_fetch_worker.query(login, passwd, org)
        @account_parameters_dirty = false
        @awaiting_account_result = true
      end

      set_status_text( @data_fetch_worker.get_status_msg )
      if @data_fetch_worker.get_status_msg != "Ready."
        dbgprint "dfw.status: #{@data_fetch_worker.get_status_msg.inspect}"
      end

      if @awaiting_account_result  &&  (@data_fetch_worker.result_ready? || @data_fetch_worker.error_state?)
        @awaiting_account_result = false

        @pstree = nil

        if @data_fetch_worker.error_state?
          org_list, pstree, photog_list = [], nil, []
        else
          org_list, pstree, photog_list = @data_fetch_worker.result
        end

        if pstree && @pstree == nil
          @pstree = pstree
        end

        update_combo(:dest_org_combo, org_list)
        update_combo(:dest_photog_combo, photog_list)

        if @refresh_col_browser
          @ui.browser_columnbrowser.reset_cache
          @ui.browser_columnbrowser.set_tree(@pstree, @ui.browser_tree_website.checked?)
          @ui.browser_columnbrowser.set_last_selected_col(-1)
          @ui.browser_columnbrowser.set_last_selected_row(-1)
          @ui.browser_columnbrowser.reset_tree(@ui.browser_tree_website.checked?)
          @ui.browser_columnbrowser.public_reload_column(0)

          if !@col_zero_node_id_to_select.nil?
            nodes = @pstree.top_level_nodes(@ui.browser_tree_website.checked?)
            new_item_row = 0
            row = 0
            nodes.each do |node|
              if node.id == @col_zero_node_id_to_select
                new_item_row = row
              end
              row = row+1
            end
            #select the new item here
            @ui.browser_columnbrowser.select_row_in_column(new_item_row, 0)
            @ui.browser_columnbrowser.set_last_selected_col(0)
            @ui.browser_columnbrowser.set_last_selected_row(new_item_row)
            items = @ui.browser_columnbrowser.get_items
            @pstree.update_selected(items[0][new_item_row])
            @col_zero_node_id_to_select = nil


          end
          @refresh_col_browser = false
        else
          @ui.browser_columnbrowser.set_tree(@pstree, @ui.browser_tree_website.checked?)
        end

        adjust_controls

      end
    end
  end
end


class PShelterAccountQueryWorker
  SUBSCRIBER_ACCT_NAME = "- my subscriber account -"
  PHOTOG_LEAVE_BLANK   = "[leave blank]"

  # ASSUMPTIONS:
  #   - Only the background thread may write to @cur_account / @cur_org,
  #     and @{orgs|collection|photog}_list.
  #     - Any thread besides the background thread must own the mutex
  #       when reading these variables.
  #     - The background thread need not own the mutex while reading
  #       these variables, but must own the mutex when writing them.

  def initialize(bridge)
#dbgprint "PShelterAccountQueryWorker.initialize()"
    @bridge = bridge
    @mutex = @bridge.create_mutex  # thread.rb Mutex can't be created in sandbox :(
    @cvar = ConditionVariable.new
    @quit = false
    @want_account = nil
    @want_org = nil
    @pstree = nil
    @status_msg = ""
    @error_state = false
    _forget_everything
    @th = Thread.new(Thread.current) do |parent_th|
      #
      # NOTE: import_thread_locals is not legal from the sandbox.
      #       Currently, we don't need it as we're not doing much
      #       with the bridge from here, and no UI calls.
      #       TODO: Maybe add @bridge.import_thread_locals ?
      #
      # PM::Dlg.import_thread_locals(parent_th)
      #
      background_query_thread
    end
  end

  def close
    @quit = true
  end

  def query(login, passwd, org=nil)
    @mutex.synchronize {
      @want_account = (login.nil?) ? nil : [login, passwd]
      @want_org = org
      if @want_account != @cur_account  ||  @want_org != @cur_org  ||  @pstree == nil
        @cvar.signal
      end
    }
  end

  def clear_pstree
    @mutex.synchronize {
      @pstree = nil
    }
  end

  def error_state?
    @mutex.synchronize {
      @error_state
    }
  end

  def result_ready?
    @mutex.synchronize {
      _account_ready?  &&  _org_ready?  &&  @pstree
    }
  end

  def result
    @mutex.synchronize {
      [@orgs_list, @pstree, @photog_list]
    }
  end

  def multi_user_access?
    @mutex.synchronize {
      _account_ready?  &&  @ps  &&  @ps.multi_user_access?
    }
  end

  def can_make_publicly_searchable?
    @mutex.synchronize {
      _account_ready?  &&  _org_ready?  &&  @ps  &&  @ps.can_collection_query?
    }
  end

  def get_status_msg
    @mutex.synchronize {@status_msg}
  end

  protected

  def set_status_msg(msg)
    @mutex.synchronize {@status_msg = msg.dup.freeze}
  end

  def background_query_thread
    @ps = nil
    @error_state = false

    until @quit
      begin
        login_account = nil
        login_org = nil

        @mutex.synchronize {
          if @error_state  ||  (_account_ready?  &&  _org_ready?)
            # wait for some new request
            @cvar.wait(@mutex)
            @error_state = false
          end

          if ! _account_ready?
            _forget_everything
          elsif ! _org_ready?
            _forget_org_related
          end

          login_account = @want_account
          login_org = @want_org
        }

        # From this point, we don't care whether @want_account / @want_org
        # change.  We are going with the spec we got... If the spec has
        # changed on us mid-stream, we'll pick that up next time through
        # the loop.

        if login_account != @cur_account
          _close_ps
          if login_account
            set_status_msg("Connecting to PhotoShelter, attempting login...")
            _open_ps(*login_account)

            orgs = @ps.orgs.collect {|o| o.name}.sort_by{|o| o.downcase}
            orgs.unshift(SUBSCRIBER_ACCT_NAME) if @ps.single_user_access?
            @mutex.synchronize { @orgs_list = orgs }
          end
          @mutex.synchronize { @cur_account = login_account }  # meaning: account_ready

        elsif @ps  &&  @ps.logged_in?  &&  (login_org != @cur_org || @pstree == nil)
          orig_login_org = login_org

          # if we're told to try to login to a nonexistent org,
          # don't bother, just pick one that does exist
          login_org = nil unless @orgs_list.include? login_org

          unless login_org
            login_org = @orgs_list.first  # just pick the first one if none given
          end
          login_org = (login_org.nil? || login_org == SUBSCRIBER_ACCT_NAME) ? nil : login_org

          if !login_org.nil?
            set_status_msg("Attempting organization login...")
            @ps.org_login(login_org)
          else
            set_status_msg("Entering subscriber account mode...")
            @ps.org_logout unless @ps.active_org.nil?
          end

          pstree, photog_list = _query_account_parameters

          @mutex.synchronize {
            @pstree = pstree
            @photog_list = photog_list
            @cur_org = orig_login_org  # meaning: org_ready
          }

          set_status_msg("Ready.")
        end

      rescue Exception => ex
        dbglog "PShelterAccountQueryWorker: exception #{ex.inspect} - #{ex.backtrace.inspect}"
        msg = ex.message
        if msg =~ /timeout/i
          if msg =~ /open/i
            msg = "Timed out connecting to remote server."
          elsif msg =~ /rbuf_fill/i
            msg = "Timed out reading from remote server."
          end
        end
        set_status_msg("Error: #{msg}")
        @error_state = true
      end
    end

    _close_ps
  end

  def _open_ps(login, passwd)
    @ps = PhotoShelter::Connection.new(@bridge, login, passwd)
    @ps.auth_login
    @ps
  end

  def _close_ps
    @ps.auth_logout if @ps rescue nil
    @ps = nil
  end

  def _account_ready?
    @want_account == @cur_account
  end

  def _org_ready?
    @want_org == @cur_org
  end

  def _forget_everything
    @cur_account = nil
    @orgs_list = []
    _forget_org_related
  end

  def _forget_org_related
    @cur_org = false  # use false instead of nil to force one pass thru org login case even for "no org"
    @pstree = []
    @photog_list = []
  end

  def _query_account_parameters
    pstree = nil
    photog_list = []
    if @ps.can_collection_query?
      set_status_msg("Querying available collection folders...")
      pstree = @ps.collection_query
    else
      pstree = @ps.empty_collection
    end
    if @ps.can_get_photog_list?
      photog_list = @ps.get_photog_list.map{|o| o.full_name}.sort_by{|o| o.downcase}
      photog_list.unshift PHOTOG_LEAVE_BLANK
    end
    [pstree, photog_list]
  end

end

class PShelterUploadProtocol

  include PShelterLogonHelper

  def initialize(pm_api_bridge)
#dbgprint "PShelterUploadProtocol.initialize()"
    @bridge = pm_api_bridge
    @ps = nil
    @ps_login = nil
  end

  def image_upload(local_filepath, remote_filename, is_retry, spec)
    # we'll need to examine the spec, and perform the
    # various login / org_login, etc.

    ensure_open_ps(spec)
    ensure_login(spec)

    @bridge.set_status_message "Uploading via secure connection..."

    rotation, is_tagged, rating = @bridge.get_rotation_tag_and_rating_state(local_filepath)

    replace_style = spec.file_exists_replace_style
    replace_style = "UPLOAD_ANYWAY" if is_retry && replace_style == "SKIP_FILE"

    remote_filename = uppercase_file_ext(remote_filename)

    final_remote_filename = @ps.image_upload(
      local_filepath, remote_filename,
      spec.photoshelter_gallery, spec.photoshelter_collection, spec.photoshelter_photog,
      rotation.to_i, rating.to_i, is_tagged,
      spec.make_publicly_searchable, replace_style)
    raise(FileSkippedException) if final_remote_filename == :skipped
    final_remote_filename
  end

  def reset_transfer_status
    @ps && @ps.reset_transfer_status
  end

  # return [bytes_to_write, bytes_written]
  def poll_transfer_status
    if @ps
      [@ps.bytes_to_write, @ps.bytes_written]
    else
      [0, 0]
    end
  end

  def abort_transfer
    @ps.abort_transfer if @ps
  end

  protected

  def uppercase_file_ext(path)
    path.sub(%r{\.[^./\\]+\z}) { $&.upcase }
  end
end

module PhotoShelter

class PhotoShelterError < RuntimeError; end
class BadHTTPResponse < PhotoShelterError; end
class BadAuthResponse < PhotoShelterError; end
class SessionError < PhotoShelterError; end

# cookie =
#   "ID=867.5309; path=/; domain=site.com, " +
#   "SESS_mem=deleted; expires=Mon, 24 Jan 2005 19:48:10 GMT; path=/; domain=.site.com, " +
#   "SESS_mem=deleted; expires=Mon, 24-Jan-2005 19:48:10 GMT; path=/; domain=.site.com, " +
#   "SESS_mem=xyzzy-plugh-plover; path=/; domain=.site.com"

class ServerCookie
  include Enumerable

  class << self
    def parse(raw_cookie)
      dat = raw_cookie.gsub(/(expires\s*=\s*\w{3}),( \d{2}[ -]\w{3}[ -]\d{4} \d\d:\d\d:\d\d GMT)/i, '\1 \2')
      cookies = dat.split(/,/)
      cookies   # we could do further parsing, but Array#each + /regexp/ will get us through for now
    end
  end

  def initialize(raw_cookie)
#dbgprint "PhotoShelter::ServerCookie.initialize()"
    @raw = raw_cookie
    @cookies = ServerCookie.parse(raw_cookie)
  end

  def each
    raise "need block" unless block_given?
    @cookies.each do |k|
      yield k
    end
  end
end

class PSOrg
  attr_reader :oid, :name
  def initialize(member,id,name)
    #dbgprint "PhotoShelter::PSOrg.initialize()"
    @oid = id
    @name = name
    @full_member = member
  end

  def full_member?
    @full_member == "t"
  end
end

class PSPho
  attr_reader :uid, :first_name, :last_name
  def initialize(doc)
#dbgprint "PhotoShelter::PSPho.initialize()"
    @uid = doc.get_elements("user_id").map{|e| e.text}.join.strip
    @first_name = doc.get_elements("first_name").map{|e| e.text}.join.strip
    @last_name = doc.get_elements("last_name").map{|e| e.text}.join.strip
  end

  def full_name
    n = []
    n << @first_name unless @first_name.empty?
    n << @last_name unless @last_name.empty?
    n.join(" ")
  end
end

class Connection

  BSAPI = "/psapi/v2/"
  APIKEY = "S67j0pDkpgk"

  attr_reader :user_email, :auth_xml, :last_response_xml, :orgs,
              :session_status, :session_first_name, :session_last_name

  def initialize(pm_api_bridge, user_email, passwd)
    #dbgprint "PhotoShelter::Connection.initialize()"
    @bridge = pm_api_bridge
    @user_email, override_uri = user_email.split(/\|/,2)
    @passwd = passwd
    @auth_xml = nil
    @auth_server_cookie_raw = nil
    @auth_client_cookie = nil
    @orgs = []
    @session_status = ""
    @session_first_name = ""
    @session_last_name = ""
    @session_token = nil
    @active_oid = nil
    @connection_uri = get_connection_uri(override_uri)
    @sitename = @connection_uri.host
    @cookies = {}
    Thread.exclusive { @@photog_name_id_mapping ||= {} } # kludge, but oh well
    @http = @bridge.open_http_connection(@sitename, @connection_uri.port)
    @http.use_ssl = (@connection_uri.scheme == "https")
    @http.open_timeout = 60
    @http.read_timeout = 180
    set_logged_out
  end

  def close
    auth_logout
    # @http.close  ### hmm http closes the socket "automatically"
  end

  # Note, this just returns true if we were logged in successfully
  # at some point.  It doesn't know whether our session may have
  # expired.
  def logged_in?
    #! @auth_client_cookie.nil?
    ! @session_token.nil?
  end

  def set_logged_out
    #@auth_client_cookie = nil
    @session_token = nil
  end

  def session_full_name
    n = []
    n << @session_first_name unless @session_first_name.empty?
    n << @session_last_name unless @session_last_name.empty?
    n.join(" ")
  end

  def active_org
    org = @orgs.find {|o| o.oid == @active_oid}
    org
  end

  def single_user_access?
    # TODO come up with a better way to figure this out
    # this is a quick fix to make it work
    # @session_status == "subscriber"
    #! @auth_client_cookie.nil?
    ! @session_token.nil?
  end

  def multi_user_access?
    @orgs.length > 0
  end

  # def async_login
  #   if logged_in?
  #     @login_th = nil
  #     return :ok
  #   end
  #   @login_th ||= Thread.new { auth_login }
  #   if @login_th.stop?
  #     begin
  #       @login_th.value
  #       if logged_in?
  #         @login_th = nil
  #         return :ok
  #       else
  #         return "Unknown error during login."
  #       end
  #     rescue Exception => ex
  #       return ex.message
  #     end
  #   end
  #   :busy
  # end


  # Authentication
  #

  #### Add comment. Switching to posting apikey/username/pw instead of a get request.

  # Authentication allows the external application to sign in to a BitShelter
  # application.  The external application will send a login and password
  # across HTTPS:
  #
  # https://www.photoshelter.com/bsapi/1.0/auth?U_EMAIL=&U_PASSWORD=
  #
  # Note: The application does not reject non-encrypted communications.  It is
  # YOUR responsibility to communicate via HTTPS.
  #
  # On failure, the response will only be errors.  On success, a session
  # Cookie will be returned in both the XML and HTTP headers (Set-Cookie) that
  # will be used for all subsequent requests to other modules.  The HTTP
  # cookie(s) must be resent as is and the format is subject to change.  The
  # XML session information can be used by the external application for
  # display purposes.
  #
  # When a valid session cookie is used with other modules, a new session
  # cookie is returned in both the error and success response conditions.  The
  # new cookie has an updated expiration time used by the system to determine
  # an idle session.  By default, sessions time out after 2 hours of
  # inactivity.
  #
  def auth_login
    begin
      #dbgprint "auth_login called"
      http = @http
      path = BSAPI+"mem/authenticate"

      parts = []
      parts << key_value_to_multipart("email", @user_email)
      parts << key_value_to_multipart("password", @passwd)
      parts << key_value_to_multipart("mode", "token")
      boundary = Digest::MD5.hexdigest(@user_email).to_s  # just hash the email itself
      headers = get_default_headers("Content-type" => "multipart/form-data, boundary=#{boundary}")
      body = combine_parts(parts, boundary)
      resp = http.post(path, body, headers)
      handle_server_response(path, resp, resp.body)
      @auth_xml = @last_response_xml
    rescue Exception => ex
      set_logged_out
      raise
    end
    true
  end


  # The authentication module will logout the current session if called
  # without any parameters. This is recommended because PhotoShelter
  # enforces a maximum number of concurrent sessions for any given user.
  #
  #TODO: rewrite logout
  def auth_logout
    return unless logged_in?
    begin
      http = @http
      path = BSAPI+"auth"
      headers = get_default_headers
      http = @http
      resp = http.get(path, headers)
    rescue StandardError
    ensure
      set_logged_out
    end
  end

  # Log in to organization of which user is a member.
  def org_login(org_name)
    perform_with_session_expire_retry {
      auth_login unless logged_in?
      org = @orgs.find {|o| o.name == org_name}
      raise(PhotoShelterError, "No organization found named '#{org_name}'") unless org
      http = @http
      path = BSAPI+"mem/organization/#{CGI.escape(org.oid)}/authenticate?format=xml"
      headers = get_default_headers
      resp = http.get(path, headers)
      handle_server_response(path, resp, resp.body)
      @active_oid = org.oid
      true
    }
  end

  # Log out of organization, back to single-user mode.
  def org_logout
    #dbgprint("calling org_logout")
    perform_with_session_expire_retry {
      auth_login unless logged_in?
      http = @http
      path = BSAPI+"mem/organization/logout?format=xml"
      headers = get_default_headers
      resp = http.get(path, headers)
      handle_server_response(path, resp, resp.body)
      @active_oid = nil
      true
    }
  end

  def create_collection_gallery(parent_id, type, name, f_list, inherit, visibility)
    #dbgprint "create_collection_gallery: #{parent_id}, #{type}, #{name}, #{f_list}, #{inherit}, #{visibility}"
    perform_with_session_expire_retry {
      auth_login unless logged_in?
      boundary = Digest::MD5.hexdigest(name).to_s  # just hash the collection_name itself
      headers = get_default_headers("Content-type" => "multipart/form-data, boundary=#{boundary}")
      parts = []
      if parent_id != ""
        parts << key_value_to_multipart("parent", parent_id)
      end
      if f_list == "t" || f_list == "f"
        parts << key_value_to_multipart("f_list", f_list)
      end
      parts << key_value_to_multipart("name", name)
      body = combine_parts(parts, boundary)
      if type == "collection"
        path = BSAPI+"mem/collection/insert?format=xml"
      else
        path = BSAPI+"mem/gallery/insert?format=xml"
      end
      resp = @http.post(path, body, headers)
      handle_server_response(path, resp, resp.body)
      id = @last_response_xml.get_elements("PhotoShelterAPI/data/id").map {|e| e.text }.join
      if(inherit == "t")
        update_collection_gallery_inherit(id, type, parent_id, inherit)
      else
        update_collection_gallery_visibility(id, type, visibility)
      end
      id
    }
  end

  def update_collection_gallery_inherit (id, type, parent_id, inherit)
    #dbgprint "update_collection_gallery_inherit: #{id}, #{inherit}"
    perform_with_session_expire_retry {
      auth_login unless logged_in?
      boundary = Digest::MD5.hexdigest(id).to_s  # just hash the collection_name itself
      headers = get_default_headers("Content-type" => "multipart/form-data, boundary=#{boundary}")
      parts = []
      parts << key_value_to_multipart("collection_id", parent_id)
      parts << key_value_to_multipart("inherit", inherit)
      body = combine_parts(parts, boundary)
      if type == "collection"
        path = BSAPI+"mem/collection/" + id + "/permission/inherit?format=xml"
      else
        path = BSAPI+"mem/gallery/" + id + "/permission/inherit?format=xml"
      end
      resp = @http.post(path, body, headers)
      handle_server_response(path, resp, resp.body)
      true
    }
  end

  def update_collection_gallery_visibility (id, type, visibility)
    #dbgprint "update_collection_gallery_visibility: #{id}, #{visibility}"
    perform_with_session_expire_retry {
      auth_login unless logged_in?
      boundary = Digest::MD5.hexdigest(id).to_s  # just hash the collection_name itself
      headers = get_default_headers("Content-type" => "multipart/form-data, boundary=#{boundary}")
      parts = []
      parts << key_value_to_multipart("mode", visibility)
      body = combine_parts(parts, boundary)
      if type == "collection"
        path = BSAPI+"mem/collection/" + id + "/visibility/update?format=xml"
      else
        path = BSAPI+"mem/gallery/" + id + "/visibility/update?format=xml"
      end
      resp = @http.post(path, body, headers)
      handle_server_response(path, resp, resp.body)
      true
    }
  end

  # Data Request
  #
  # A data request is one that an external application requests some
  # information from a BitShelter application.  Such requests include: all
  # collection names for logged in user, gallery names that are public for logged
  # in user.  Data requests may result in an XML response or a more specific
  # Content-type (e.g.  download full sized image).  The format of which is
  # determined by the type of request.
  #
  #

  # <?xml version="1.0"?>
  # <PhotoShelterAPI version="1.0"><status>ok</status></PhotoShelterAPI>

  # Album Query and response contents:
  #
  # https://www.photoshelter.com/bsapi/1.0/alb-qry
  #
  # (<collection><A_ID>id</A_ID><A_NAME>name</A_NAME>...</collection>)*
  #
  def collection_query
    perform_with_session_expire_retry {
      auth_login unless logged_in?
      raise(PhotoShelterError, "Collection query access not available for this account or organization.") unless can_collection_query?
      path = BSAPI+"mem/collection/root/children?format=xml"
      headers = get_default_headers
      http = @http
      resp = http.get(path, headers)
      handle_server_response(path, resp, resp.body)
#@last_response_xml.write($stderr, 0)
      PSTree.new(@last_response_xml, self)
    }
  end

  def collection_children_query(id)
    perform_with_session_expire_retry {
      auth_login unless logged_in?
      raise(PhotoShelterError, "Collection query access not available for this account or organization.") unless can_collection_query?
      path = BSAPI+"mem/collection/"+id+"/children?format=xml"
      headers = get_default_headers
      http = @http
      resp = http.get(path, headers)
      handle_server_response(path, resp, resp.body)
#@last_response_xml.write($stderr, 0)
      @last_response_xml
    }
  end

  def empty_collection
    xml = '<?xml version="1.0"?>' + "\n"
    xml += '<PhotoShelterAPI version="1.0"><status>ok</status><data></data></PhotoShelterAPI>'
    PSTree.new(@bridge.xml_document_parse(xml), self)
  end

  # Are we allowed to collection_query in our current context?
  # (Answer depends on whether we're logged into an organization,
  # what our access is within that org, or whether we're logged
  # into a single user account, etc.)
  def can_collection_query?
    org = active_org
    if org
      org.full_member?
    else
      single_user_access?
    end
  end

  # You can derive the list of available photographers by
  # calling the "org-usr-pho-qry" module (when authenticated
  # to an organization.)
  #
  # https://www.photoshelter.com/bsapi/1.0/org-usr-pho-qry
  #
  def get_photog_list
    #dbgprint("inside get_photog_list")
    photogs = []
    perform_with_session_expire_retry {
      auth_login unless logged_in?
      path = BSAPI+"mem/organization/#{CGI.escape(@active_oid)}/photographers?format=xml"
      headers = get_default_headers
      http = @http
      resp = http.get(path, headers)
      handle_server_response(path, resp, resp.body)
# @last_response_xml.write($stderr, 0)
      photogs = parse_photog_list(@last_response_xml)
      update_photog_name_id_mapping(photogs)
      photogs
    }
      photogs
  end

  def can_get_photog_list?
    #dbgprint("inside can_get_photog_list active_org = #{active_org.inspect}")
    ! active_org.nil?
  end

  # Test whether <filename> exists within <collection_id>.
  #
  def image_exist(gallery_id, filename)
    gallery_id = "Default" if gallery_id.strip.empty?
    perform_with_session_expire_retry {
      auth_login unless logged_in?
      path = BSAPI+"mem/image/query?format=xml"
      boundary = Digest::MD5.hexdigest(gallery_id).to_s  # just hash the collection_name itself
      headers = get_default_headers("Content-type" => "multipart/form-data, boundary=#{boundary}")
      parts = []
      parts << key_value_to_multipart("gallery_id", gallery_id)
      parts << key_value_to_multipart("file_name", filename)
      body = combine_parts(parts, boundary)
      resp = @http.post(path, body, headers)
      handle_server_response(path, resp, resp.body)
      #@last_response_xml.write($stderr, 0)
     # dbgprint @last_response_xml.inspect
      exists = false
      total = 0
      total = @last_response_xml.get_elements("PhotoShelterAPI/data/total").map {|e| e.text }.join
      if total.to_i > 0
        exists = true
      end
      #dbgprint "image_exist('#{gallery_id}','#{filename}') = #{exists}"
      exists
    }
  end

  def find_unique_filename_on_server(collection_id, filename)
    base, ext = filename.split(/\.(?=[^.]*\z)/)
    "A".upto("Z".succ) do |mod|
      return filename unless image_exist(collection_id, filename)
      filename = "#{base}#{mod}.#{ext}"
    end
    raise PhotoShelterError, "Failed all attempts to find unique name for file #{base}.#{ext} in collection #{collection_id}."
  end

  # Functional Request
  #
  # Image Upload (using enctype=multipart/form-data):
  #
  # https://www.photoshelter.com/bsapi/1.0/img-upl?I_FILE[]=&I_F_PUB=
  #
  # Album Insert:
  #
  # https://www.photoshelter.com/bsapi/1.0/alb-ins?A_NAME=
  #
  # In the above two examples, the response will be XML.
  #
  #

  # Image Upload
  #
  # The image upload module accepts an image upload.  If no collection is specified
  # (ID or name) the image is placed in the Default collection.  If an collection ID or
  # collection name is specified and it exists, the image is placed in that collection.
  # If the specified collection name does not exist, a new collection is created with
  # that name and the image is placed in the new collection.  This module must be
  # contacted using the HTTP multi-part form variable encoding type and
  # I_FILE[] must be a form array type
  #
  # The img-upl module of the API accepts two parameters: I_IS_TAGGED and
  # I_ANGLE.  if I_IS_TAGGED=t it will tag the image upon upload.  the I_ANGLE
  # parameter (if specified) has to be either 90, 180, or 270.
  #
  # Returns:
  #   :skipped (symbol) if (replace_style == "SKIP_FILE") and file
  #     already exists on server
  #   Else, returns final_remote_filename, whatever filename we used
  #     to upload after whatever collision renaming may have occurred.

  def get_gallery_to_upload_to(parent_id)
    xml_resp = collection_children_query(parent_id)
    if xml_resp
      data = xml_resp.get_elements("PhotoShelterAPI/data").first
      data or raise("bad server response - collection root element missing")
      gallery_id = ""
      children = data.get_elements("children")
      children.each do |child|
        type = child.get_elements("type").first
        type_text = type ? type.text : ""
        type_text = "" unless type_text
        if type_text == "gallery"
          gallery_node = child.get_elements("gallery").first
          gal = gallery_node.get_elements("name").first
          gallery_name = gal ? gal.text : ""
          gallery_name = "" unless gallery_name
          if gallery_name == "Uploader"
            gal = gallery_node.get_elements("id").first
            gallery_id = gal ? gal.text : ""
            gallery_id = "" unless gallery_id
          end
        end
      end
    end
    gallery_id
  end

  def image_upload(local_pathtofile, remote_filename, gallery_id, collection_id, photog_name, rotation, rating, is_tagged, publicly_searchable, replace_style)
    perform_with_session_expire_retry {
      auth_login unless logged_in?
#      photog_name = nil if photog_name.to_s.strip.empty?
#      rotation = rotation.to_i

      if gallery_id == "" && collection_id != ""
        gallery_id = get_gallery_to_upload_to(collection_id)
      end

      if replace_style == "SKIP_FILE"
        return :skipped if image_exist(gallery_id, remote_filename)
      elsif replace_style == "RENAME_BEFORE_UPLOADING"
        remote_filename = find_unique_filename_on_server(gallery_id, remote_filename)
      end

      # binary_data = File.open(local_pathtofile, "rb") {|f| f.read}
      binary_data = @bridge.read_file_for_upload(local_pathtofile)
      boundary = Digest::MD5.hexdigest(local_pathtofile).to_s  # just hash the filename itself
      headers = get_default_headers("Content-type" => "multipart/form-data, boundary=#{boundary}")
      parts = []
      parts << binary_to_multipart("file", remote_filename, binary_data)

      if gallery_id != ""
        parts << key_value_to_multipart("gallery_id", gallery_id)
      else
        parts << key_value_to_multipart("parent_id", collection_id)
      end

      #      if gallery_id.index("BY_NAME:") == 0
#        gallery_id = gallery_id.sub(/BY_NAME:/, "")
#        parts << key_value_to_multipart("A_NAME", gallery_id)
#      else
#        parts << key_value_to_multipart("A_ID", gallery_id)
#      end
      if photog_name
        photog_id = photog_name_to_id(photog_name)
        if photog_id
          parts << key_value_to_multipart("photographer_id", photog_id)
        end
      end
#      if rotation != 0
#        parts << key_value_to_multipart("I_ANGLE", rotation)
#      end
#      parts << key_value_to_multipart("I_RATING", rating)
#      if is_tagged
#        parts << key_value_to_multipart("I_IS_TAGGED", "t")
#      end
      if publicly_searchable
        parts << key_value_to_multipart("f_searchable", "t")
      end
      body = combine_parts(parts, boundary)
      path = BSAPI+"mem/image/upload"
      http = @http
      resp = http.post(path, body, headers)
      handle_server_response(path, resp, resp.body)
      File.join(gallery_id, remote_filename)
    }
  end

  def reset_transfer_status
    @http.reset_transfer_status
  end

  def bytes_to_write
    @http.bytes_to_write
  end

  def bytes_written
    @http.bytes_written
  end

  def abort_transfer
    @http.abort_transfer
  end

  protected

  def get_connection_uri(override_uri_str)
    uri = nil
    if override_uri_str && !override_uri_str.to_s.strip.empty?
      uri = URI.parse(override_uri_str) rescue nil
    end

    unless uri
      uri = URI.parse("https://www.photoshelter.com:443")
    end

    uri
  end

  def get_default_headers(additional_headers={})
    headers = {}
    if @auth_client_cookie
      headers['Cookie'] = @auth_client_cookie
    end
    # if @connection_uri.user || @connection_uri.password
    #    user, pass = @connection_uri.user.to_s, @connection_uri.password.to_s
    #    headers['Authorization'] = 'Basic ' + encode64("#{user}:#{pass}").chop
    #  end
    headers['X-PS-Api-Key'] = APIKEY
    if !@session_token.nil?
      headers['X-PS-Auth-Token'] = @session_token
    end
    headers.merge(additional_headers)
  end

  # Call given block.  Retry up to 1 time if we
  # get a SessionError.
  def perform_with_session_expire_retry
    result = nil
    attempts = 1
    begin
      result = yield
    rescue SessionError
      set_logged_out
      raise if attempts > 1
      attempts += 1
      retry
    end
    result
  end

  def get_errmsg_for_data(data)
    xml = @bridge.xml_document_parse(data)
    error = xml.get_elements("PhotoShelterAPI/error/message").map {|e| e.text }.join
    error
  end

  def handle_server_response(path, resp, data)
    raise(BadHTTPResponse, get_errmsg_for_data(data)) unless resp.code == "200"
    raise(BadAuthResponse, get_errmsg_for_data(data)) unless resp['content-type'] == "text/xml"

    @last_response_xml = @bridge.xml_document_parse(data)
    raise_on_failure(@last_response_xml)
    @session_status = @last_response_xml.get_elements("PhotoShelterAPI/status").map {|e| e.text }.join
    if path == BSAPI+"mem/authenticate"
      @orgs = parse_organizations(@last_response_xml)
      session_token = @last_response_xml.get_elements("PhotoShelterAPI/data/token").collect {|e| e.text}.join(" ")
      if session_token != ""
        @session_token = session_token
      end
      #dbgprint("session token = #{@session_token}")
    end

  end

  def raise_on_failure(doc)
    #TODO handle errors
    status = doc.get_elements("PhotoShelterAPI/status").collect {|e| e.text}.join(" ")
    if status != "ok"
      errclass = doc.get_elements("BitShelterAPI/response/error/class").collect {|e| e.text}.join(" ")
      errclass ||= "UnknownError"
      errmsg = doc.get_elements("BitShelterAPI/response/error/message").collect {|e| e.text}.join(" ")
      errmsg ||= "Unknown error."
      ex = (errclass =~ /session/i) ? SessionError : PhotoShelterError
      raise ex, "#{errclass}: #{errmsg}"
    end
  end

  def parse_organizations(doc)
    orgs = []
    #{"member":"t","id":"O0000AoXP1xI.fPs","name":"PS Test Agency"}
    node = doc.get_elements("PhotoShelterAPI/data/org").each {|e|
      child_node = e.get_elements("id").first
      id = child_node ? child_node.text : ""
      id = "" unless id

      child_node = e.get_elements("member").first
      member = child_node ? child_node.text : ""
      member = "" unless member

      child_node = e.get_elements("name").first
      name = child_node ? child_node.text : ""
      name = "" unless name

      orgs << PSOrg.new(member,id,name)
    }
    orgs
  end

  def parse_photog_list(doc)
    photogs = []
    doc.get_elements("PhotoShelterAPI/data/photographers").each {|e| photogs << PSPho.new(e)}
    photogs
  end

  def update_photog_name_id_mapping(photogs)
    Thread.exclusive {
      photogs.each do |o|
        @@photog_name_id_mapping[o.full_name] = o.uid
      end
    }
  end

  def photog_name_to_id(photog_name)
    Thread.exclusive { @@photog_name_id_mapping[photog_name] }
  end

  def accept_server_cookie(svk)
#    dbgprint svk
    if svk
      @auth_server_cookie_raw = svk
      @auth_client_cookie = gen_client_cookie(svk)
    end
  end

  def gen_client_cookie(server_cookie_raw)
    sk = ServerCookie.new(server_cookie_raw)
    new_cookies_raw = sk.reject {|k| k =~ /deleted/}
    new_cookies = new_cookies_raw.map {|k| k.split(/;/)[0].strip}
    new_cookies.each do |k|
      key, val = k.split(/=/)
      @cookies[key.strip] = val.to_s.strip
    end
    baked = []
    @cookies.keys.sort.each do |key|
      baked << "#{key}=#{@cookies[key]}"
    end
    baked.join("; ")
  end

  def key_value_to_multipart(key_name, value)
     %{Content-Disposition: form-data; name="#{key_name}"\r\n\r\n#{value}\r\n}
  end

  def binary_to_multipart(key_name, remote_filename, binary_data)
    %{Content-Disposition: form-data; name="#{key_name}"; filename="#{remote_filename}"\r\n} +
    %{Content-Transfer-Encoding: binary\r\n} +
    %{Content-Type: image/jpeg\r\n\r\n} + binary_data + %{\r\n}
  end

  def combine_parts(parts, boundary)
    parts << key_value_to_multipart("format", "xml")
    separator = "--#{boundary}\r\n"
    data = separator + parts.join(separator) + "--#{boundary}--"
  end

end  # class Connection


class ConnectionCache
  def initialize
#dbgprint "PhotoShelter::ConnectionCache.initialize()"
    @cache = {}
  end

  def get(user_email, passwd)
    key = "#{user_email}\t#{passwd}"
    Thread.exclusive {
      @cache[key] ||= Connection.new(user_email, passwd)
    }
  end
end

PSItem = Struct.new(:id, :parent_id, :type, :name, :htmlname, :listed, :mode, :description)

class PSTree
  include Enumerable

  def initialize(xml_resp, connection)
    @connection = connection
    if xml_resp
      root = xml_resp.get_elements("PhotoShelterAPI/data").first
      root or raise("bad server response - collection root element missing")
      @by_id = {}
      @children = {}
      @children["root"] = []
      collection_tmp_array = []
      gallery_tmp_array = []
      website_tmp_array = []
      non_website_tmp_array = []

      @top_level_nodes = get_node_children(root, "root")
      @top_level_nodes.each { |item|
        #dbgprint "PSItem (#{item.id}, #{item.parent_id}, #{item.type}, #{item.name}, #{item.listed}, #{item.mode}, #{item.description})"
        @by_id[item.id] = item
        @children["root"] << item.id
        if item.type == "collection"
          collection_tmp_array << item
        else
          gallery_tmp_array << item
        end

        if item.listed == "t"
          website_tmp_array << item
        else
          non_website_tmp_array << item
        end
      }
      @top_level_nodes = @top_level_nodes.sort_by { |k| k.name.downcase }
      @top_level_collections = collection_tmp_array.sort_by { |k| k.name.downcase }
      @top_level_galleries = gallery_tmp_array.sort_by { |k| k.name.downcase }
      @top_level_website_nodes = website_tmp_array.sort_by { |k| k.name.downcase }
      @top_level_non_website_nodes = non_website_tmp_array.sort_by { |k| k.name.downcase }
    end

    @selected = PSItem.new("", "", "", "", "", "", "", "")
  end

  def get_children(node)
    xml_resp = @connection.collection_children_query(node.id)
    if xml_resp
      data = xml_resp.get_elements("PhotoShelterAPI/data").first
      data or raise("bad server response - collection root element missing")
      tmp_array = []
      tmp_children = get_node_children(data, node.id)
      if tmp_children != [nil]
        tmp_children.each { |item|
          @by_id[item.id] = item
          tmp_array << item
        }
      end
      @children[node.id] = tmp_array
    end
    @children[node.id]

  end

  def get_cache
    @children
  end

  def set_cache(children)
    @children = children
  end

  def get_cached_children(node)
    if @children[node.id]
      @children[node.id]
    else
      get_children(node)
    end
  end

  def get_item_by_id(item_id)
    @by_id[item_id]
  end

  def item_id_for_path_title(title)
    item = @by_path_title[title]
    item_id = item ? item.id : ""
  end

  def is_item_listed(item_id)
    item = @by_id[item_id]
    listed = item ? item.listed : false
  end

  def get_item_permission(item_id)
    item = @by_id[item_id]
    permission = item ? item.mode : "everyone"
  end

  def top_level_collections
    paths_array = []
    @top_level_collections.each { |node|
      paths_array << node.name
    }
    paths_array
  end
#
#  def top_level_nodes
#    @top_level_nodes
#  end

  def top_level_nodes(on_web)
    if on_web
      @top_level_website_nodes
    else
      @top_level_non_website_nodes
    end
  end

  def top_level_galleries
    paths_array = []
    @top_level_galleries.each { |node|
      paths_array << node.name
    }
    paths_array
  end

  def update_selected(node)
    @selected = node
  end

  def get_selected
    @selected
  end

    private

#  take a node, gather children and return
  def get_node_children(parent,parent_id)
    @kids = []
    children = parent.get_elements("children")
    children.each do |child|
      ps = construct_node(child,parent_id)
      if ps != nil
        @kids << ps
      end
    end
    if !@kids.empty?
      @kids = @kids.sort_by { |k| k.name.downcase }
    end
    @kids
  end

  def construct_node(node,parent_id)
    type = get_child_text(node, "type")
    if type == "collection"
       listed = get_child_text(node, "listed")
       collection = node.get_elements("collection").first
       mode = get_child_text(collection, "mode")
       id = get_child_text(collection, "id")
       name = get_child_text(collection, "name")
       htmlname = basic_unescape_html(name)
       description = get_child_text(collection, "description")
       type = "collection"
       ps = PSItem.new(id, parent_id, type, name, htmlname, listed, mode, description)
    end
    if type == "gallery"
       listed = get_child_text(node, "listed")
       gallery = node.get_elements("gallery").first
       mode = get_child_text(gallery, "mode")
       id = get_child_text(gallery, "id")
       name = get_child_text(gallery, "name")
       htmlname = CGI.unescapeHTML(name)
       description = get_child_text(gallery, "description")
       type = "gallery"
       ps = PSItem.new(id, parent_id, type, name, htmlname, listed, mode, description)
    end
    ps
  end

  def basic_unescape_html(str)
    str.gsub(/&(amp|quot|gt|lt);/) do
      match = $1.dup
      case match
      when 'amp'                 then '&'
      when 'quot'                then '"'
      when 'gt'                  then '>'
      when 'lt'                  then '<'
      else
        "&#{match};"
      end
    end
  end


  def get_child_text(node, child_name)
    child_node = node.get_elements(child_name).first
    txt = child_node ? child_node.text : ""
    txt = "" unless txt
    txt
  end


end

end  # module PhotoShelter

