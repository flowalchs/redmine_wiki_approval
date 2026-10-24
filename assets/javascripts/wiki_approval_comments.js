// Inline comments for wiki pages (Redmine >= 6, stimulus from the core importmap)
import { Controller } from '@hotwired/stimulus'
import { application } from 'controllers/application'

const CONTEXT_LENGTH = 64
// a short quote needs some matching context, otherwise it would jump to other text
const MIN_CONTEXT_MATCH = 8
const UNIQUE_QUOTE_LENGTH = 32
let textareaCounter = 0
const STORAGE_KEY = 'rwa-wiki-comments-highlights'

// text of all text nodes below root, with the offset of every node
class TextIndex {
  constructor(root) {
    this.entries = []
    this.text = ''

    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
    let node
    while ((node = walker.nextNode())) {
      const start = this.text.length
      this.text += node.data
      this.entries.push({ node, start, end: this.text.length })
    }
  }

  // [start, end] text offsets of a dom range, null if outside
  rangeOffsets(range) {
    const hits = this.entries.filter(e => range.intersectsNode(e.node))
    if (hits.length === 0) return null

    const first = hits[0]
    const last = hits[hits.length - 1]
    const start = first.node === range.startContainer ? first.start + range.startOffset : first.start
    const end = last.node === range.endContainer ? last.start + range.endOffset : last.end
    return end > start ? [start, end] : null
  }

  // best match of quote, scored by the surrounding prefix/suffix
  find(quote, prefix = '', suffix = '') {
    if (!quote) return null

    // older comments may contain CRLF from the form submit
    quote = quote.replace(/\r\n/g, '\n')
    prefix = prefix.replace(/\r\n/g, '\n')
    suffix = suffix.replace(/\r\n/g, '\n')

    let best = null
    let bestScore = -1
    let index = this.text.indexOf(quote)
    for (let n = 0; index !== -1 && n < 1000; n++) {
      const before = this.text.slice(Math.max(0, index - prefix.length), index)
      const after = this.text.slice(index + quote.length, index + quote.length + suffix.length)
      const score = commonSuffix(before, prefix) + commonPrefix(after, suffix)
      if (score > bestScore) {
        best = [index, index + quote.length]
        bestScore = score
      }
      index = this.text.indexOf(quote, index + 1)
    }

    const required = quote.length >= UNIQUE_QUOTE_LENGTH ? 0 : Math.min(MIN_CONTEXT_MATCH, prefix.length + suffix.length)
    return bestScore >= required ? best : null
  }
}

function commonPrefix(a, b) {
  let i = 0
  while (i < a.length && i < b.length && a[i] === b[i]) i++
  return i
}

function commonSuffix(a, b) {
  let i = 0
  while (i < a.length && i < b.length && a[a.length - 1 - i] === b[b.length - 1 - i]) i++
  return i
}

class WikiCommentsController extends Controller {
  static targets = ['content', 'panel', 'thread', 'toggle', 'inlineForm']
  static values = {
    filter: { type: String, default: 'open' },
    highlights: { type: Boolean, default: true },
    canAdd: Boolean,
    commentLabel: String,
    helpUrl: String,
    previewUrl: String,
    previousLabel: String,
    nextLabel: String
  }

  connect() {
    this.highlightsValue = this.storedHighlights()
    this.onSelection = this.onSelection.bind(this)
    this.onSidebarClick = this.onSidebarClick.bind(this)
    this.onKeydown = this.onKeydown.bind(this)
    this.onHashChange = this.onHashChange.bind(this)

    document.addEventListener('mouseup', this.onSelection)
    document.addEventListener('keyup', this.onSelection)
    document.addEventListener('click', this.onSidebarClick)
    document.addEventListener('keydown', this.onKeydown)
    window.addEventListener('hashchange', this.onHashChange)

    this.refresh()

    // link from an orphaned thread to its start version: #comment-<number>
    setTimeout(() => this.onHashChange(), 100)
  }

  // #comment-<number> (journal link or link from another version): jump to the text and open the thread
  onHashChange() {
    const match = window.location.hash.match(/^#comment-(\d+)$/)
    const thread = match && this.panelTarget.querySelector(`#comment-${match[1]}`)?.closest('.rwa-thread')
    if (!thread) return

    if (this.marksFor(thread.dataset.commentId).length > 0) {
      this.scrollToMark({ params: { id: thread.dataset.commentId } })
    } else {
      if (this.filterValue !== 'all' && thread.dataset.status !== this.filterValue) this.filterValue = 'all'
      this.flash([thread])
    }
  }

  disconnect() {
    document.removeEventListener('mouseup', this.onSelection)
    document.removeEventListener('keyup', this.onSelection)
    document.removeEventListener('click', this.onSidebarClick)
    document.removeEventListener('keydown', this.onKeydown)
    window.removeEventListener('hashchange', this.onHashChange)
    this.closePopover()
  }

  // --- panel state ---

  filter({ params }) {
    this.filterValue = params.filter
  }

  filterValueChanged() {
    this.updateEmptyState()
  }

  toggleHighlights(event) {
    this.highlightsValue = event.target.checked
    try { localStorage.setItem(STORAGE_KEY, this.highlightsValue ? '1' : '0') } catch (e) {}
  }

  highlightsValueChanged() {
    if (this.hasToggleTarget) this.toggleTarget.checked = this.highlightsValue
  }

  storedHighlights() {
    try { return localStorage.getItem(STORAGE_KEY) !== '0' } catch (e) { return true }
  }

  updateEmptyState() {
    if (!this.hasPanelTarget) return

    this.panelTarget.querySelectorAll('.rwa-filter').forEach(tab => {
      tab.classList.toggle('selected', tab.classList.contains(`rwa-filter-${this.filterValue}`))
    })

    const visible = this.threadTargets.filter(t => this.filterValue === 'all' || t.dataset.status === this.filterValue)
    this.panelTarget.classList.toggle('rwa-has-threads', visible.length > 0)
  }

  // sidebar links are outside of the controller element
  onSidebarClick(event) {
    const link = event.target.closest('[data-rwa-filter]')
    if (!link) return

    event.preventDefault()
    this.filterValue = link.dataset.rwaFilter

    // jump to the first commented text, the panel only without inline anchors
    const group = link.dataset.rwaGroup
    let mark
    if (group) {
      const ids = this.threadTargets.filter(t => t.dataset.group === group).map(t => t.dataset.commentId)
      mark = [...this.contentTarget.querySelectorAll('mark.rwa-mark')].find(m => ids.includes(m.dataset.commentId))
    } else {
      mark = this.contentTarget.querySelector(this.filterValue === 'all' ? 'mark.rwa-mark' : `mark.rwa-mark-${this.filterValue}`)
    }
    if (!mark) {
      const heading = group && this.panelTarget.querySelector(`.rwa-group-${group}`)
      ;(heading || this.panelTarget).scrollIntoView({ behavior: 'smooth', block: 'start' })
      return
    }

    this.scrollToMark({ params: { id: mark.dataset.commentId } })
  }

  onKeydown(event) {
    if (event.key === 'Escape') this.closePopover()
  }

  // --- highlights ---

  refresh() {
    this.highlightsValueChanged()
    this.removeMarks()

    const anchors = []
    const index = new TextIndex(this.contentTarget)
    this.threadTargets.forEach(thread => {
      const quote = thread.dataset.quote
      if (!quote) return

      const offsets = index.find(quote, thread.dataset.prefix, thread.dataset.suffix)
      thread.classList.toggle('rwa-orphan', !offsets)
      if (offsets) anchors.push({ thread, offsets })
    })

    // wrapping splits text nodes, so the index is rebuilt for each anchor
    anchors.forEach(({ thread, offsets }) => {
      this.wrap(new TextIndex(this.contentTarget), offsets, thread)
    })

    this.updateEmptyState()
  }

  // redmine formatting toolbar (jstoolbar), the preview needs a unique textarea id
  initToolbar(textarea) {
    if (typeof window.jsToolBar !== 'function' || textarea.dataset.rwaToolbar) return

    textarea.id = `rwa-comment-text-${++textareaCounter}`
    textarea.dataset.rwaToolbar = '1'
    const toolbar = new window.jsToolBar(textarea)
    toolbar.setHelpLink(this.helpUrlValue)
    toolbar.setPreviewUrl(this.previewUrlValue)
    toolbar.draw()
  }

  wrap(index, [start, end], thread) {
    index.entries
      .filter(e => e.end > start && e.start < end && e.node.data.trim() !== '')
      .forEach(e => {
        let node = e.node
        const from = Math.max(start, e.start) - e.start
        const to = Math.min(end, e.end) - e.start
        if (to < node.data.length) node.splitText(to)
        if (from > 0) node = node.splitText(from)

        const mark = document.createElement('mark')
        mark.className = `rwa-mark rwa-mark-${thread.dataset.status}`
        mark.dataset.commentId = thread.dataset.commentId
        node.parentNode.insertBefore(mark, node)
        mark.appendChild(node)
      })
  }

  removeMarks() {
    this.contentTarget.querySelectorAll('mark.rwa-mark').forEach(mark => {
      const parent = mark.parentNode
      while (mark.firstChild) parent.insertBefore(mark.firstChild, mark)
      parent.removeChild(mark)
      parent.normalize()
    })
  }

  marksFor(id) {
    return this.contentTarget.querySelectorAll(`mark.rwa-mark[data-comment-id="${id}"]`)
  }

  activate(id, active) {
    this.marksFor(id).forEach(m => m.classList.toggle('rwa-mark-active', active))
    const thread = this.threadById(id)
    if (thread) thread.classList.toggle('rwa-thread-active', active)
  }

  threadById(id) {
    return this.threadTargets.find(t => t.dataset.commentId === String(id))
  }

  scrollToMark({ params }) {
    const marks = this.marksFor(params.id)
    if (marks.length === 0) return

    if (!this.highlightsValue) this.highlightsValue = true
    const thread = this.threadById(params.id)
    if (thread && thread.dataset.status !== this.filterValue && this.filterValue !== 'all') this.filterValue = 'all'

    marks[0].scrollIntoView({ behavior: 'smooth', block: 'center' })
    this.flash(marks)
    this.showThread(params.id, marks[0])
  }

  flash(elements) {
    elements.forEach(el => {
      el.classList.remove('rwa-flash')
      void el.offsetWidth
      el.classList.add('rwa-flash')
    })
  }

  // --- popover ---

  onSelection(event) {
    if (this.popover && this.popover.contains(event.target)) return

    // wait until the browser has updated the selection
    const popover = this.popover
    setTimeout(() => this.showCommentButton(popover), 0)
  }

  showCommentButton(popoverBefore) {
    const selection = window.getSelection()
    if (!selection || selection.isCollapsed || selection.rangeCount === 0) {
      // a click outside closes the popover, written text in a form is kept,
      // a popover opened by the same click (mark, quote, sidebar) stays
      if (this.popover && this.popover === popoverBefore && !this.popover.classList.contains('rwa-popover-form')) this.closePopover()
      return
    }
    if (!this.canAddValue || !this.hasInlineFormTarget) return

    const range = selection.getRangeAt(0)
    if (!this.contentTarget.contains(range.commonAncestorContainer)) return

    const index = new TextIndex(this.contentTarget)
    const offsets = index.rangeOffsets(range)
    if (!offsets) return

    const [start, end] = offsets
    const quote = index.text.slice(start, end)
    if (quote.trim() === '') return

    this.selectionAnchor = {
      quote,
      prefix: index.text.slice(Math.max(0, start - CONTEXT_LENGTH), start),
      suffix: index.text.slice(end, end + CONTEXT_LENGTH)
    }

    const button = document.createElement('button')
    button.type = 'button'
    button.className = 'rwa-add-button'
    button.textContent = this.commentLabelValue
    button.addEventListener('mousedown', event => event.preventDefault())
    button.addEventListener('click', () => this.showInlineForm())

    this.openPopover(button, range.getBoundingClientRect(), 'rwa-popover-button')
  }

  showInlineForm() {
    const anchor = this.selectionAnchor
    if (!anchor) return

    const rect = this.popover.getBoundingClientRect()
    const fragment = this.inlineFormTarget.content.cloneNode(true)
    const form = fragment.querySelector('form')
    form.elements.quote.value = anchor.quote
    form.elements.prefix.value = anchor.prefix
    form.elements.suffix.value = anchor.suffix
    form.querySelector('.rwa-quote').textContent = anchor.quote.length > 300 ? `${anchor.quote.slice(0, 300)}…` : anchor.quote

    this.openPopover(form, rect, 'rwa-popover-form')
    this.initToolbar(form.elements.text)
    form.elements.text.focus()
  }

  // delegated from the content: redmine rebuilds some elements (e.g. the copy wrapper
  // of <pre>), listeners on the marks themselves would get lost
  openThread(event) {
    if (window.getSelection().toString() !== '') return

    // innermost visible mark, hidden ones (resolved while filtering open ones, or all switched off) are plain text
    const selector = this.markSelector()
    let mark = event.target.closest('mark.rwa-mark')
    while (mark && !mark.matches(selector)) mark = mark.parentElement?.closest('mark.rwa-mark')
    if (!mark) return

    event.preventDefault()
    this.showThread(mark.dataset.commentId, mark)
  }

  hoverMark(event) {
    const mark = event.target.closest('mark.rwa-mark')
    if (!mark || (event.relatedTarget && mark.contains(event.relatedTarget))) return

    this.activate(mark.dataset.commentId, event.type === 'mouseover')
  }

  // thread as popover below the commented text
  showThread(id, anchor) {
    const thread = this.threadById(id)
    if (!thread) return

    const clone = thread.cloneNode(true)
    clone.removeAttribute('id')
    clone.removeAttribute('data-wiki-comments-target')
    clone.classList.remove('rwa-thread-active', 'rwa-flash')
    clone.querySelectorAll('[id]').forEach(el => el.removeAttribute('id'))
    clone.querySelector('.rwa-quote')?.remove()
    // typed text and open forms are not cloned
    clone.querySelectorAll('form').forEach(form => {
      form.reset()
      form.hidden = true
    })
    clone.querySelectorAll('.rwa-comment-body').forEach(body => { body.hidden = false })
    // cloned toolbars have no event handlers, they are drawn again on demand
    clone.querySelectorAll('.jstBlock').forEach(block => {
      const textarea = block.querySelector('textarea')
      delete textarea.dataset.rwaToolbar
      textarea.classList.remove('hidden')
      block.replaceWith(textarea)
    })

    // journal styles of redmine need the .journals container
    const content = document.createElement('div')
    content.className = 'journals'
    content.append(clone)
    // previous/next in the header, left of the actions
    clone.querySelector('.journal-actions')?.prepend(this.threadNavigation(id))
    this.openPopover(content, anchor.getBoundingClientRect(), 'rwa-popover-thread')
    this.popoverThreadId = String(id)
  }

  // marks shown with the current filter
  // same as the css: open marks are always shown, resolved ones with the resolved or all filter
  markSelector() {
    if (!this.highlightsValue) return 'mark.rwa-mark-none'
    return this.filterValue === 'open' ? 'mark.rwa-mark-open' : 'mark.rwa-mark'
  }

  // previous/next within the group of the shown thread, in document order:
  // open and resolved in this revision together, resolved in earlier revisions on its own
  navigationGroup(thread) {
    return thread?.dataset.group === 'earlier' ? 'earlier' : 'active'
  }

  navigableIds(id) {
    const group = this.navigationGroup(this.threadById(id))
    const relevant = new Set(this.threadTargets
      .filter(t => this.navigationGroup(t) === group)
      .map(t => t.dataset.commentId))
    const ids = [...this.contentTarget.querySelectorAll('mark.rwa-mark')]
      .map(m => m.dataset.commentId)
      .filter(id => relevant.has(id))
    return [...new Set(ids)]
  }

  threadNavigation(id) {
    const nav = document.createElement('span')
    nav.className = 'rwa-popover-nav'
    const ids = this.navigableIds(id)
    const position = ids.indexOf(String(id))
    if (ids.length < 2 || position === -1) return nav

    const button = (step, label, text) => {
      const b = document.createElement('button')
      b.type = 'button'
      b.title = label
      b.textContent = text
      b.dataset.action = 'wiki-comments#step'
      b.dataset.wikiCommentsStepParam = step
      return b
    }
    const counter = document.createElement('span')
    counter.textContent = `${position + 1} / ${ids.length}`
    nav.append(button(-1, this.previousLabelValue, '‹'), counter, button(1, this.nextLabelValue, '›'))
    return nav
  }

  step({ params }) {
    const ids = this.navigableIds(this.popoverThreadId)
    const position = ids.indexOf(this.popoverThreadId)
    if (ids.length === 0) return

    const next = ids[(position + params.step + ids.length) % ids.length]
    this.scrollToMark({ params: { id: next } })
  }

  openPopover(content, rect, kind) {
    this.closePopover()

    const popover = document.createElement('div')
    popover.className = `rwa-popover ${kind}`
    popover.appendChild(content)
    this.element.appendChild(popover)
    popover.style.maxWidth = `${this.element.clientWidth}px`

    // the wrapper is not positioned (it would cover the floating contextual menu),
    // so the popover is placed relative to its offset parent and kept inside the wrapper
    const parent = popover.offsetParent || document.body
    const base = parent.getBoundingClientRect()
    const bounds = this.element.getBoundingClientRect()
    const left = Math.min(Math.max(rect.left, bounds.left), Math.max(bounds.left, bounds.right - popover.offsetWidth))
    popover.style.top = `${rect.bottom - base.top + parent.scrollTop + 6}px`
    popover.style.left = `${left - base.left + parent.scrollLeft}px`
    this.popover = popover
  }

  closePopover() {
    if (this.popover) this.popover.remove()
    this.popover = null
  }

  // --- forms and actions ---

  // reply, or quote a comment like in redmine issues
  reply({ params, target }) {
    const form = target.closest('.rwa-thread').querySelector('.rwa-reply-form')
    if (params.text) {
      const quoted = params.text.split(/\r?\n/).map(line => `> ${line}`).join('\n')
      const text = form.elements.text
      text.value = `${text.value.trim() ? text.value.trimEnd() + '\n\n' : ''}${quoted}\n\n`
    }
    this.showForm(form)
  }

  edit(event) {
    const comment = event.target.closest('.rwa-comment')
    comment.querySelector('.rwa-comment-body').hidden = true
    this.showForm(comment.querySelector('.rwa-edit-form'))
  }

  showPageForm() {
    this.showForm(this.panelTarget.querySelector('.rwa-page-comment-form'))
  }

  showForm(form) {
    if (!form) return

    form.hidden = false
    this.initToolbar(form.elements.text)
    form.elements.text.focus()
  }

  cancelForm(event) {
    const form = event.target.closest('form')
    form.hidden = true
    form.reset()
    const body = form.closest('.rwa-comment')?.querySelector('.rwa-comment-body')
    if (body) body.hidden = false
  }

  async submit(event) {
    event.preventDefault()
    const form = event.target
    const result = await this.request(form.action, 'POST', new FormData(form), form)
    if (result) {
      this.closePopover()
      this.focusThread(result.id)
    }
  }

  async resolve({ params, target }) {
    const body = new FormData()
    body.append('resolved', params.resolved)
    await this.request(params.url, 'PUT', body, target)
  }

  async destroy({ params, target }) {
    if (params.confirm && !window.confirm(params.confirm)) return

    await this.request(params.url, 'DELETE', null, target)
  }

  async request(url, method, body, source) {
    const buttons = source.closest('form, .journal-actions')?.querySelectorAll('button, input[type=submit]') || []
    buttons.forEach(b => { b.disabled = true })

    try {
      const response = await fetch(url, {
        method,
        body,
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        },
        credentials: 'same-origin'
      })
      const data = await response.json().catch(() => null)

      if (!response.ok) {
        window.alert((data && data.errors && data.errors.join('\n')) || response.statusText)
        return null
      }

      this.render(data)
      return data
    } catch (error) {
      window.alert(error.message)
      return null
    } finally {
      buttons.forEach(b => { b.disabled = false })
    }
  }

  render(data) {
    // the popover shows a copy of the old state
    this.closePopover()
    this.panelTarget.innerHTML = data.panel

    const sidebar = document.getElementById('rwa-comments-sidebar')
    if (sidebar) sidebar.outerHTML = data.sidebar

    this.refresh()
  }

  focusThread(id) {
    const thread = id && this.panelTarget.querySelector(`.rwa-comment[data-id="${id}"]`)?.closest('.rwa-thread')
    if (!thread) return

    if (this.filterValue !== 'all' && thread.dataset.status !== this.filterValue) this.filterValue = 'all'
    this.flash([thread])
  }
}

application.register('wiki-comments', WikiCommentsController)
