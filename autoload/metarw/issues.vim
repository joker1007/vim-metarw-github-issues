"=============================================================================
" FILE: metarw/issues.vim
" AUTHOR:  Tomohiro Hashidate (joker1007) <kakyoin.hierophant@gmail.com>
" License: MIT license  {{{
"     Permission is hereby granted, free of charge, to any person obtaining
"     a copy of this software and associated documentation files (the
"     "Software"), to deal in the Software without restriction, including
"     without limitation the rights to use, copy, modify, merge, publish,
"     distribute, sublicense, and/or sell copies of the Software, and to
"     permit persons to whom the Software is furnished to do so, subject to
"     the following conditions:
"
"     The above copyright notice and this permission notice shall be included
"     in all copies or substantial portions of the Software.
"
"     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"     OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"     MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"     IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"     CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"     TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"     SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
" }}}
"=============================================================================

let s:save_cpo = &cpo
set cpo&vim

if !exists('g:github_token')
  echohl ErrorMsg | echomsg "require 'g:github_token' variables" | echohl None
  finish
endif

if !exists('g:github_user')
  echohl ErrorMsg | echomsg "require 'g:github_user' variables" | echohl None
  finish
endif

if !executable('curl')
  echohl ErrorMsg | echomsg "require 'curl' command" | echohl None
  finish
endif

let s:comment_separator ="\n------------------------------------------------------------\n"

let s:endpoint_url = "https://api.github.com/"

let g:github_request_header = {
        \ "User-Agent" : "vim-metarw-github-issues",
        \ "Content-type" : "application/json",
        \ "Authorization" : "token " . g:github_token,
        \ }

function! metarw#issues#api_url(path, ...) " {{{
  let query = []

  if exists('g:github_issues_per_page')
    call add(query, "per_page=" . g:github_per_page)
  endif

  if a:0 > 0
    for [key, val] in items(a:000[0])
      call add(query, key . "=" . val)
    endfor
  endif

  let path = s:endpoint_url . a:path

  if !empty(query)
    let path = path . "?" . join(query, "&")
  endif

  return path
endfunction " }}}

function! s:parse_title() " {{{
  return getline(1)
endfunction " }}}

function! s:parse_body() " {{{
  return split(join(getline(4, "$"), "\n"), s:comment_separator)[0]
endfunction " }}}

function! s:parse_labels() " {{{
  let line = getline(2)

  if line =~ "^\s*$/"
    return []
  else
    return split(line, " ")
  endif
endfunction " }}}

function! s:labels_to_line(_) " {{{
  return join(map(a:_, 'v:val.name'), " ")
endfunction " }}}

function! s:next_page_link(_, header) " {{{
  if join(a:header, ', ') =~# "Link: <.*>"
    let options = deepcopy(a:_.options)
    let options.page = options.page + 1
    let query = []
    for [key, val] in items(options)
      call add(query, key . "=" . val)
    endfor
    let link_to_next = {
          \ "label" : "[Fetch next page]",
          \ "fakepath" : split(a:_.fakepath, "?")[0] . '?' . join(query, "&")
          \ }
    return link_to_next
  else
    return {}
  endif
endfunction " }}}

function! s:construct_post_data() " {{{
  let labels = s:parse_labels()

  let data = {
        \ "title" : s:parse_title(),
        \ "labels" : labels,
        \ "body" : s:parse_body(),
        \ }

  return data
endfunction " }}}

function! s:post_current(repo) " {{{
  let data = s:construct_post_data()
  let json = webapi#json#encode(data)
  let res = webapi#http#post(metarw#issues#api_url("repos/" . a:repo . "/issues"), json, g:github_request_header)
  let content = webapi#json#decode(res.content)

  if res.status =~ "^2.*"
    echomsg content.html_url
    return ['done', '']
  else
    return ['error', 'Failed to post new item']
  endif
endfunction " }}}

function! s:update_issue(repo, number) " {{{
  let data = s:construct_post_data()
  let json = webapi#json#encode(data)
  let res = webapi#http#post(metarw#issues#api_url("repos/" . a:repo . "/issues/" . a:number), json, g:github_request_header, "PATCH")
  let content = webapi#json#decode(res.content)

  if res.status =~ "^2.*"
    echomsg content.url
    return ['done', '']
  else
    return ['error', 'Failed to update item']
  endif
endfunction " }}}

function! s:read_content(repo, number) " {{{
  let res = webapi#http#get(metarw#issues#api_url("repos/" . a:repo . '/issues/' . a:number), {}, g:github_request_header)

  if res.status !~ "^2.*"
    return ['error', 'Failed to fetch item']
  endif

  let content = webapi#json#decode(res.content)

  let body = join([content.title, s:labels_to_line(content.labels), "", substitute(content.body, '\r', '',  "g")], "\n")
  put =body
  set ft=markdown

  let b:issue_metadata = {
        \ 'html_url' : content.html_url,
        \ 'state' : content.state,
        \ 'user' : content.user.login,
        \ 'repo' : a:repo,
        \ 'number' : a:number,
        \}

  command! -buffer IssueBrowse call s:open_browser()
  command! -buffer IssueCommentPost
        \ call github#comment#open(b:issue_metadata.repo, b:issue_metadata.number)

  call s:fetch_comments(a:repo, a:number)
  return ['done', '']
endfunction " }}}

function! s:fetch_comments(repo, number) " {{{
  let res = webapi#http#get(metarw#issues#api_url("repos/" . a:repo . '/issues/' . a:number . '/comments'), {}, g:github_request_header)

  if res.status !~ "^2.*"
    return ['error', 'Failed to fetch item']
  endif

  let content = webapi#json#decode(res.content)

  let comments = map(content,
        \ '{"body": v:val.body, "user": v:val.user.login, "id": v:val.id, "created_at" : v:val.created_at}')

  for comment in comments
    put =s:comment_separator
    let info = comment.user . " posted at " . comment.created_at "\n"
    put =info
    let body = "\n" . comment.body
    put =body
  endfor
endfunction " }}}

function! s:issue_title(issue, view_repository) " {{{
  let title = a:issue.title
  let labels = join(map(a:issue.labels, '"[" . v:val.name . "]"'), "")

  if !empty(labels)
    let title = labels . " " . title
  endif

  let title = "#" . a:issue.number . " " . title

  if type(a:issue.assignee) == 4
    let title = title . " assigned to " . a:issue.assignee.login
  endif

  if a:view_repository
    let regex = 'repos/\(.*/.*\)/issues/\d\+'
    let l = matchstr(a:issue.url, regex, "\1", "")
    let repo = substitute(l, regex, '\1', '')
    let title = repo . " " . title
  endif

  return title
endfunction " }}}

function! s:read_issue_list(_, view_repository) " {{{
  let res = webapi#http#get(metarw#issues#api_url(a:_.path, a:_.options), {}, g:github_request_header)
  if res.status !~ "^2.*"
    return ['error', 'Failed to fetch issues']
  endif

  let content = webapi#json#decode(res.content)
  let regex = '\(repos/.*/.*/\d\+\)'
  let list = []

  for issue in content
    let label = s:issue_title(issue, a:view_repository)
    let issue_fakepath = "issues:" . matchstr(issue.url, regex, "\1", "")
    call add(list, {"label" : label, "fakepath" : issue_fakepath})
  endfor

  let next_page_link = s:next_page_link(a:_, res.header)
  if !empty(next_page_link)
    call add(list, next_page_link)
  endif

  return ["browse", list]
endfunction " }}}

function! s:parse_options(str) " {{{
  let result = {}
  let pairs = split(a:str, "&")
  for p in pairs
    let [key, value] = split(p, '=')
    let result[key] = value
  endfor
  return result
endfunction " }}}

function! s:open_browser() " {{{
  if exists('b:issue_metadata')
    call openbrowser#open(b:issue_metadata.html_url)
  else
    echoerr 'Current buffer is not github issue'
  endif
endfunction " }}}

function! s:parse_incomplete_fakepath(incomplete_fakepath) " {{{
  let _ = {
        \ 'mode' : '',
        \ 'repo' : '',
        \ 'number' : '',
        \ 'options' : {"page": 1}
        \ }

  let fragments = split(a:incomplete_fakepath, '^\l\+\zs:', !0)
  if len(fragments) <= 1
    echoerr 'Unexpected a:incomplete_fakepath:' string(a:incomplete_fakepath)
    throw 'metarw:github#e1'
  endif

  let _.scheme = fragments[0]

  let path_fragments = split(fragments[1], '?', !0)
  " parse option parameter
  if len(path_fragments) == 2
    call extend(_.options, s:parse_options(path_fragments[1]), 'force')
    let fragments[1] = path_fragments[0]
  elseif len(path_fragments) >= 3
    echoerr 'path is invalid'
    return _
  endif

  if !empty(fragments[1])
    let fragments = [fragments[0]] + split(fragments[1], '[\/]', !0)

    let target = fragments[1]

    if target == "repos"
      if len(fragments) == 4
        let _.mode = 'repo_list'
        let _.repo = fragments[2] . '/' . fragments[3]
      elseif len(fragments) == 6
        let _.mode = 'issue'
        let _.repo = fragments[2] . '/' . fragments[3]
        let _.number = fragments[5]
      endif
    elseif target == "orgs"
      if len(fragments) == 3
        let _.mode = 'org_list'
        let _.repo = fragments[2]
      endif
    elseif target == "user"
      if len(fragments) == 2
        let _.mode = 'user_list'
      endif
    endif
  endif

  return _
endfunction " }}}

function! metarw#issues#read(fakepath) " {{{
  let _ = s:parse_incomplete_fakepath(a:fakepath)
  let _.fakepath = a:fakepath
  if _.mode == "repo_list"
    let _.path = "repos/" . _.repo . "/issues"
    return s:read_issue_list(_, 0)
  elseif _.mode == "org_list"
    let _.path = "orgs/" . _.repo . "/issues"
    return s:read_issue_list(_, 1)
  elseif _.mode == "user_list"
    let url = s:api_path("user/issues", _.options)
    let _.path = "user/issues"
    return s:read_issue_list(_, 1)
  elseif _.mode == "issue"
    return s:read_content(_.repo, _.number)
  else
    return ['done', '']
  endif
endfunction " }}}

function! metarw#issues#write(fakepath, line1, line2, append_p) " {{{
  let _ = s:parse_incomplete_fakepath(a:fakepath)
  if _.mode == "repo_list"
    let result = s:post_current(_.repo)
  elseif _.mode == "issue"
    let result = s:update_issue(_.repo, _.number)
  else
    let result = ['done', '']
  endif
  return result
endfunction " }}}

" Nop
function! metarw#issues#complete(arglead, cmdline, cursorpos) " {{{
  return []
endfunction " }}}

let &cpo = s:save_cpo
unlet s:save_cpo
