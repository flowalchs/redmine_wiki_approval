# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class WikiApprovalTest < WikiApproval::Test::IntegrationCase
  def setup
    log_user('admin', 'admin')
  end

  test "should create a project with wiki, show it and save the first wiki page" do
    # 1. Projekt erstellen
    get '/projects/new'
    assert_response :success

    post '/projects', params: {
      project: {
        name: 'Wiki Test Project',
        identifier: 'wiki-test-project',
        enabled_module_names: ['wiki', 'wiki_approval']
      }
    }

    # Redirect nach erfolgreichem Erstellen
    assert_response :redirect
    follow_redirect!
    assert_response :success

    assert_match /Successful creation/i, response.body

    # 2. Wiki aufrufen
    get '/projects/wiki-test-project/wiki'
    assert_response :success

    # edit form
    assert_select 'form#wiki_form.new_content[action=?][method=?]',
                  '/projects/wiki-test-project/wiki/Wiki', 'post'

    # 3. Erste Wiki-Seite speichern
    put '/projects/wiki-test-project/wiki/Wiki', params: {
      content: {
        text: 'Das ist der Inhalt der ersten Wiki-Seite.',
        comments: 'Initial version'
      }
    }
    assert_response :redirect
    follow_redirect!
    assert_response :success

    # Verifikation
    assert_select 'div.wiki', /Das ist der Inhalt der ersten Wiki-Seite./
  end
end
