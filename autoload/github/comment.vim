"=============================================================================
" FILE: github/comment.vim
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

let s:comment_buffer_open_cmd = "botright split github_comment"

function! github#comment#open(repo, number)
  let bufnr = bufwinnr('github_comment')
  if bufnr > 0
    exec bufnr.'wincmd w'
  else
    execute s:comment_buffer_open_cmd
    execute '15 wincmd _'
    call s:init_github_comment_buffer()
  endif

  let b:issue_metadata = {
        \ "repo" : a:repo,
        \ "number" : a:number,
        \ }
endfunction

function! s:init_github_comment_buffer()
  setlocal bufhidden=wipe
  setlocal buftype=acwrite
  setlocal nobuflisted
  setlocal noswapfile
  setlocal modifiable
  setlocal nomodified
  setlocal nonumber
  setlocal ft=markdown

  if !exists('b:github_comment_buf_write_cmd')
    augroup GithubIssueComment
      autocmd!
      autocmd BufWriteCmd <buffer> call s:post_comment()
    augroup END
    let b:github_comment_buf_write_cmd = 1
  endif

  :0
  startinsert!
endfunction

function! s:post_comment()
  let body = join(getline(1, "$"), "\n")
  let repo = b:issue_metadata.repo
  let number = b:issue_metadata.number
  if !empty(body)
    let res = webapi#http#post(metarw#issues#api_url("repos/" . repo . '/issues/' . number . "/comments"), webapi#json#encode({"body" : body}), g:github_request_header)

    if res.status =~ "^2.*"
      echomsg "Posted."
      setlocal nomodified
      bd!
    else
      echohl Error | echo 'Failed to post comment [' . res.message . ']' | echohl None
    endif
  else
    echohl Error | echo 'write comment body' | echohl None
  endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
