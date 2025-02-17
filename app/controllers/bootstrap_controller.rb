# frozen_string_literal: true

class BootstrapController < ApplicationController
  include ApplicationHelper

  skip_before_action :redirect_to_login_if_required

  # This endpoint allows us to produce the data required to start up Discourse via JSON API,
  # so that you don't have to scrape the HTML for `data-*` payloads
  def index
    locale = script_asset_path("locales/#{I18n.locale}")

    preload_anonymous_data
    if current_user
      current_user.sync_notification_channel_position
      preload_current_user_data
    end

    @stylesheets = []
    add_scheme(scheme_id, 'all')
    add_scheme(dark_scheme_id, '(prefers-color-scheme: dark)')
    if rtl?
      add_style(mobile_view? ? :mobile_rtl : :desktop_rtl)
    else
      add_style(mobile_view? ? :mobile : :desktop)
    end
    add_style(:admin) if staff?
    Discourse.find_plugin_css_assets(
      include_official: allow_plugins?,
      include_unofficial: allow_third_party_plugins?,
      mobile_view: mobile_view?,
      desktop_view: !mobile_view?,
      request: request
    ).each do |file|
      add_style(file, plugin: true)
    end
    add_style(mobile_view? ? :mobile_theme : :desktop_theme) if theme_ids.present?

    extra_locales = []
    if ExtraLocalesController.client_overrides_exist?
      extra_locales << ExtraLocalesController.url('overrides')
    end
    if staff?
      extra_locales << ExtraLocalesController.url('admin')
    end

    plugin_js = Discourse.find_plugin_js_assets(
      include_official: allow_plugins?,
      include_unofficial: allow_third_party_plugins?,
      request: request
    ).map { |f| script_asset_path(f) }

    bootstrap = {
      theme_ids: theme_ids,
      title: SiteSetting.title,
      current_homepage: current_homepage,
      locale_script: locale,
      stylesheets: @stylesheets,
      plugin_js: plugin_js,
      plugin_test_js: [script_asset_path("plugin_tests")],
      setup_data: client_side_setup_data,
      preloaded: @preloaded,
      html: create_html,
      theme_html: create_theme_html,
      html_classes: html_classes,
      html_lang: html_lang,
      login_path: main_app.login_path
    }
    bootstrap[:extra_locales] = extra_locales if extra_locales.present?
    bootstrap[:csrf_token] = form_authenticity_token if current_user

    render_json_dump(bootstrap: bootstrap)
  end

private
  def add_scheme(scheme_id, media)
    return if scheme_id.to_i == -1
    theme_id = theme_ids&.first

    if style = Stylesheet::Manager.color_scheme_stylesheet_details(scheme_id, media, theme_id)
      @stylesheets << { href: style[:new_href], media: media }
    end
  end

  def add_style(target, opts = nil)
    if styles = Stylesheet::Manager.stylesheet_details(target, 'all', theme_ids)
      styles.each do |style|
        @stylesheets << {
          href: style[:new_href],
          media: 'all',
          theme_id: style[:theme_id],
          target: style[:target]
        }.merge(opts || {})
      end
    end
  end

  def create_html
    html = {}
    return html unless allow_plugins?

    add_plugin_html(html, :before_body_close)
    add_plugin_html(html, :before_head_close)
    add_plugin_html(html, :before_script_load)
    add_plugin_html(html, :header)

    html
  end

  def add_plugin_html(html, key)
    add_if_present(html, key, DiscoursePluginRegistry.build_html("server:#{key.to_s.dasherize}", self))
  end

  def create_theme_html
    theme_html = {}
    return theme_html if customization_disabled?

    theme_view = mobile_view? ? :mobile : :desktop

    add_if_present(theme_html, :body_tag, Theme.lookup_field(theme_ids, theme_view, 'body_tag'))
    add_if_present(theme_html, :head_tag, Theme.lookup_field(theme_ids, theme_view, 'head_tag'))
    add_if_present(theme_html, :header, Theme.lookup_field(theme_ids, theme_view, 'header'))
    add_if_present(theme_html, :translations, Theme.lookup_field(theme_ids, :translations, I18n.locale))
    add_if_present(theme_html, :js, Theme.lookup_field(theme_ids, :extra_js, nil))

    theme_html
  end

  def add_if_present(hash, key, val)
    hash[key] = val if val.present?
  end

end
