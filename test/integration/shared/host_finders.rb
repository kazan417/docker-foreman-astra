module HostFinders
  extend ActiveSupport::Concern

  def switch_form_tab_to_interfaces
    switch_form_tab('Interfaces')
    disable_interface_modal_animation
  end

  def disable_interface_modal_animation
    page.evaluate_script('document.getElementById("interfaceModal").classList.remove("fade")')
  end

  def go_to_interfaces_tab
    # go to New Host page
    assert_new_button(current_hosts_path, "Create Host", new_host_path)
    # switch to interfaces tab
    switch_form_tab_to_interfaces
  end

  def close_interfaces_modal
    button = page.find(:button, 'Ok')
    page.scroll_to(button)
    button.click # close interfaces
    # wait for the dialog to close
    page.has_no_css?('#interfaceModal.in')
  end

  def add_interface
    page.find(:button, '+ Add Interface').click
    page.find('#interfaceModal')
    close_interfaces_modal
  end

  def modal
    page.find('#interfaceModal.in')
  end

  def table
    page.find("table#interfaceList")
  end

  def assert_interface_change(change, &block)
    original_interface_count = table.all('tr', :visible => true).count
    yield
    assert_equal original_interface_count + change, table.all('tr', :visible => true).count
  end

  def index_modal
    page.find('#confirmation-modal')
  end

  def multiple_actions_div
    page.find('#submit_multiple')
  end

  def click_on_inherit(attribute, prefix: 'host_')
    find("##{prefix}#{attribute}_id").ancestor('.input-group').find(".input-group-btn .btn").click
  end

  def current_hosts_path(*args)
    ApplicationHelper.current_hosts_path(*args)
  end
end
