# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiEditTest < WikiApproval::Test::ControllerCase
  tests WikiController

  def setup
    super
    set_session_user(@jsmith)
    @page = WikiPage.find_by(id: 1)
    @page.content ||= WikiContent.create!(page: @page, text: 'test')
  end

  test "should render wiki edit draft comment" do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'true'

    get :edit, params: { project_id: @project.id, id: @page.title }
    assert_response :success

    # 1. draft checkbox checked and disabled
    assert_select 'input[type=checkbox][name=status][id=status][value=draft][disabled=disabled][checked=checked]'
    # 3. commend required just in javascript
    assert_includes @response.body, 'span.textContent = " *"'

    # update page
    put :update, params: { project_id: @project.id, id: @page.title,
      content: {
        text: 'new text in textarea',
        comments: 'my comment'
      },
      status_disabled: 'true',
      status: 'draft'}

    assert_response :redirect

    get :edit, params: { project_id: @project.id, id: @page.title }
    assert_response :success

    @page.reload

    # draft status in db
    approval = WikiApprovalWorkflow.for_wiki(@page.id, @page.content.version).first
    assert_equal 'draft', approval.status
  end

  test "should render wiki edit with no draft no comment" do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'true'

    get :edit, params: { project_id: @project.id, id: @page.title }
    assert_response :success

    # 1. draft checkbox  disabled=false checked=false
    assert_select 'input[type=checkbox][name=status][id=status][value=draft]' do |elements|
      el = elements.first
      assert_nil el['disabled'], 'not disabled'
      assert_nil el['checked'], 'not checked'
    end

    # 1. find <label>, with "Comment"
    assert_select 'label', text: /Comment/ do |labels|
      labels.each do |label|
        # 2. Label without <span class="required">
        assert_select label, 'span.required', count: 0
      end
    end
  end

  test 'should render wiki edit with draft checked disabled version required' do
    @page = WikiPage.find(11)
    @page.content ||= WikiContent.create!(page: @page, text: 'test')
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version] = 'true'

    get :edit, params: { project_id: @project.id, id: @page.title }
    assert_response :success

    # 1. draft checkbox checked and disabled, because of last version approved
    assert_select 'input[type=checkbox][name=status][id=status][value=draft][disabled=disabled][checked=checked]'
  end

  test 'should render wiki edit with draft checked disabled required' do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version] = 'false'

    get :edit, params: { project_id: @project.id, id: @page.title }
    assert_response :success

    # 1. draft checkbox checked and disabled, because of approval required no draft
    assert_select 'input[type=checkbox][name=status][id=status][value=draft][disabled=disabled][checked=checked]'
  end

  test 'should render wiki edit with draft not checked disabled' do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version] = 'false'

    get :edit, params: { project_id: @project.id, id: @page.title }
    assert_response :success

    # 1. draft checkbox not checked and disabled, because of approval enabled, each version is published
    assert_select 'input[type=checkbox][name=status][id=status][value=draft][disabled=disabled]'
    assert_select 'input[type=checkbox][name=status][id=status][value=draft][checked]', 0
  end

  test 'should render wiki edit with draft not checked disabled only draft' do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_content_draft] = 'false'

    get :edit, params: { project_id: @project.id, id: @page.title }
    assert_response :success

    assert_select 'input[type=checkbox][name=status][id=status][value=draft]' do |elements|
      el = elements.first
      assert_nil el['disabled'], 'not disabled'
      assert_nil el['checked'], 'not checked'
    end
    # no contentDraft button
    assert_select "input[type=submit][name=draft]", false
  end

  test "should not update wiki page comment required" do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'true'

    # update page
    assert_no_difference 'WikiApprovalWorkflow.count' do
      put :update, params: { project_id: @project.id, id: @page.title,
        content: {
          text: 'new text in textarea',
          comments: ''
        },
        status_disabled: 'true',
        status: 'draft'}
    end

    assert_response :success
    assert_select "div#errorExplanation"
  end

  test "should not save new wiki page comment required" do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'true'

    # new page
    assert_no_difference ['WikiPage.count', 'WikiApprovalWorkflow.count'] do
      put :update, params: { project_id: @project.id, id: 'newWikPageApproval',
        content: {
          text: 'new text in textarea',
          comments: ''
        },
        status_disabled: 'true',
        status: 'draft'}
    end

    assert_response :success
    assert_select "div#errorExplanation"
  end

  test "should update wiki page comment required" do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'true'

    # update page
    assert_difference 'WikiApprovalWorkflow.count', 1 do
      put :update, params: { project_id: @project.id, id: @page.title,
        content: {
          text: 'new text in textarea',
          comments: 'should update comment'
        },
        status_disabled: 'true',
        status: 'draft'}
    end

    assert_response :redirect
    assert_select "div#errorExplanation", false
  end

  test "should save new wiki page comment required" do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'true'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'true'

    # new page
    assert_difference ['WikiPage.count', 'WikiApprovalWorkflow.count'] do
      put :update, params: { project_id: @project.id, id: 'newWikPageApproval',
        content: {
          text: 'new text in textarea',
          comments: 'comment new'
        },
        status_disabled: 'true',
        status: 'draft'}
    end

    assert_response :redirect
    assert_select "div#errorExplanation", false
  end

  test 'should render wiki edit with content draft buttons' do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_enabled] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_version] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_content_draft] = 'true'

    get :edit, params: { project_id: @project.id, id: @page.title }
    assert_response :success

    assert_select 'input[type=checkbox][name=status][id=status][value=draft]', false

    # Formular-Button "Save draft" prüfen
    assert_select "input[type=submit][name=draft]" do
      assert_select "[value='Save draft']"
      assert_select "[data-disable-with='Save draft']"
    end

    # Cancel‑Link prüfen
    assert_select "a[href='/projects/ecookbook/wiki/CookBook_documentation']", text: "Cancel"

    assert_select "textarea", /CookBook documentation/
  end

  test 'should render wiki edit with version of content draft back to prev version' do
    old_version_count = @page.content.versions.count
    old_draft_count = WikiApprovalDraft.count

    put :update, params: { project_id: @project.id, id: @page.title,
        content: {
          text: 'new contentDraft',
          comments: 'comment new'
        },
        draft: 'true'}

    assert_response :success

    assert_select "textarea", /new contentDraft/
    assert_includes flash[:notice], I18n.t(:notice_successful_update)

    # 1. Keine neue WikiContent-Version erzeugt
    assert_equal old_version_count, @page.content.versions.count
    # 2. Ein neuer WikiApprovalDraft wurde erzeugt
    assert_equal old_draft_count + 1, WikiApprovalDraft.count
    assert_select "a[href='/projects/ecookbook/wiki/CookBook_documentation/edit?version=3']"

    # load old last version
    get :edit, params: { project_id: @project.id, id: @page.title, version: 3 }
    assert_response :success

    assert_select "textarea", /CookBook documentation/
    textarea = css_select('#content_text').first
    captured_text = textarea.text.strip if textarea

    # save again
    put :update, params: { project_id: @project.id, id: @page.title,
      content: {
        text: captured_text,
        comments: 'comment new'
      },
      draft: 'true'}

    assert_response :success

    assert_select "textarea", /CookBook documentation/
    assert_equal old_version_count, @page.content.versions.count
    # Draft count same as before
    assert_equal old_draft_count, WikiApprovalDraft.count
    # version link
    assert_select "a[href='/projects/ecookbook/wiki/CookBook_documentation/edit?version=3']", false
  end

  test 'should render wiki edit with version of content draft section' do
    # because of redmint 4.2
    Setting.text_formatting = 'textile'

    # save multiple sections
    put :update, params: { project_id: @project.id, id: @page.title,
      content: {
        text: "h1. section 1\n\nfirst\n\nh1. section 2\n\nsecond",
        comments: 'some section'
      }}

    old_version_count = @page.content.versions.count
    old_draft_count = WikiApprovalDraft.count

    get :edit, params: { project_id: @project.id, id: @page.title, section: 2 }
    assert_response :success

    assert_select "textarea", /h1. section 2/
    assert_select "textarea", /second/
    assert_select "textarea", { text: /newText/, count: 0 }
    assert_select "textarea", { text: /first/, count: 0 }

    put :update, params: { project_id: @project.id, id: @page.title, section: 2,
      content: {
        text: "h1. section 2\n\nsecond\n\nnewText"
      },
      draft: 'true'}
    assert_response :success

    assert_equal old_version_count, @page.content.versions.count
    assert_equal old_draft_count + 1, WikiApprovalDraft.count

    assert_select "textarea", /h1. section 2/
    assert_select "textarea", /second/
    assert_select "textarea", /newText/
    assert_select "textarea", { text: /first/, count: 0 }

    get :edit, params: { project_id: @project.id, id: @page.title, section: 1 }

    assert_select "textarea", /h1. section 1/
    assert_select "textarea", /first/
    assert_select "textarea", { text: /testtest/, count: 0 }
    assert_select "textarea", { text: /h1. section 2/, count: 0 }
    assert_select "textarea", { text: /second/, count: 0 }
    assert_select "textarea", { text: /newText/, count: 0 }

    # save on section 1, but full text in new version
    put :update, params: { project_id: @project.id, id: @page.title, section: 1,
      content: {
        text: "h1. section 1\n\nfirst\n\ntesttest"
      }}
    assert_response :redirect

    assert_equal old_version_count + 1, @page.content.versions.count
    assert_equal old_draft_count, WikiApprovalDraft.count

    get :edit, params: { project_id: @project.id, id: @page.title }

    assert_select "textarea", /h1. section 1/
    assert_select "textarea", /first/
    assert_select "textarea", /testtest/
    assert_select "textarea", /h1. section 2/
    assert_select "textarea", /second/
    assert_select "textarea", /newText/
  end

  test 'test should update contentDraft wiki with attachment' do
    plugin_fixture_path = File.expand_path('../fixtures/wiki_approval_settings.yml', __dir__)
    uploaded_file = fixture_file_upload(plugin_fixture_path, 'text/yaml')

    assert_difference ['Attachment.count', 'WikiApprovalDraft.count'] do
      put :update, params: {
        project_id: @project.id,
        id: @page.title,
        content: {
          text: "new Attachment content draft"
        },
        draft: "true",
        attachments: {
          '1' => { 'file' => uploaded_file, 'description' => 'new' }
        }
      }
    end

    assert_response :success
  end

  test "should update wiki page to puplished cancel other approvers" do
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_comment] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_required] = 'false'
    Setting.plugin_redmine_wiki_approval[:wiki_approval_settings_draft_enabled] = 'true'

    @page = WikiPage.find_by(id: 11)

    # update page, with same content
    put :update, params: {
      project_id: @project.id,
      id: @page.title,
      content: {
        text: @page.content.text,
        comments: '',
        version: @page.content.version
      },
      status_disabled: 'true',
      status: 'published'
    }

    assert_response :redirect

    # published status in db
    approval = WikiApprovalWorkflow.for_wiki(@page.id, @page.content.version).first
    assert_equal 'published', approval.status

    approval.approval_steps.each do |step|
      assert_equal 'canceled', step.status
    end
  end
end
