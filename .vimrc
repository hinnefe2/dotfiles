" most Vundle stuff copied from
" https://realpython.com/blog/python/vim-and-python-a-match-made-in-heaven/

set nocompatible              " required
filetype off                  " required

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

" alternatively, pass a path where Vundle should install plugins
"call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'gmarik/Vundle.vim'

" Add all your plugins here (note older versions of Vundle used Bundle instead of Plugin)
Plugin 'tpope/vim-sensible'
Plugin 'tmhedberg/SimpylFold'
" Bundle 'Valloric/YouCompleteMe'
Plugin 'scrooloose/syntastic'
" Plugin 'andviro/flake8-vim'
Plugin 'scrooloose/nerdtree'
Plugin 'tpope/vim-fugitive'
Plugin 'tpope/vim-surround'
Plugin 'davidhalter/jedi-vim'
Plugin 'ervandew/supertab'
Plugin 'SirVer/ultisnips'
Plugin 'honza/vim-snippets'
Plugin 'ctrlpvim/ctrlp.vim'
Plugin 'vim-airline/vim-airline'
Plugin 'leafgarland/typescript-vim'
Bundle "lepture/vim-jinja"
Plugin 'rafi/awesome-vim-colorschemes'

" NERDTree options
let NERDTreeIgnore=['\.pyc$', '\~$'] "ignore files in NERDTree
let g:NERDTreeChDirMode = 2

" ctrlp options
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlP'

" make YCM compatible with UltiSnips (using supertab)
let g:ycm_key_list_select_completion = ['<C-n>', '<Down>']
let g:ycm_key_list_previous_completion = ['<C-p>', '<Up>']
" let g:SuperTabDefaultCompletionType = '<C-n>'

" if using SuperTab w/out YCM
let g:SuperTabDefaultCompletionType = "<c-x><c-o>"

" better key bindings for UltiSnipsExpandTrigger
let g:UltiSnipsExpandTrigger = "<c-h>"
let g:UltiSnipsSnippetsDir = "~/.vim/snips"
let g:UltiSnipsSnippetDirectories=["snips", "UltiSnips"]
let g:UltiSnipsListSnippets="<c-l>"
let g:UltiSnipsJumpForwardTrigger="<c-j>"
let g:UltiSnipsJumpBackwardTrigger="<c-k>"
let g:UltiSnipsEditSplit = "vertical"
let g:ultisnips_python_style="numpy"
nnoremap <leader>ue :UltiSnipsEdit<cr>

" python script to create docstring snippets
source ~/.vim/docsnip.py.vim
source ~/.vim/passthrough.py.vim

" airline options
set laststatus=2
let g:airline#extensions#tabline#enabled = 1

" Show just the filename
" let g:airline#extensions#tabline#fnamemod = ':t'

let python_highlight_all=1
syntax on

" All of your Plugins must be added before the following line
call vundle#end()            " required
filetype plugin indent on    " required

" Allows opening new files without closing a previous one"
set hidden

" Enable syntax highlighting "
syntax enable

" copied from http://nvie.com/posts/how-i-boosted-my-vim/"
set nowrap        " don't wrap lines
set tabstop=4     " a tab is four spaces
set backspace=indent,eol,start
                    " allow backspacing over everything in insert mode
set autoindent    " always set autoindenting on
set copyindent    " copy the previous indentation on autoindenting
set shiftwidth=4  " number of spaces to use for autoindenting
set shiftround    " use multiple of shiftwidth when indenting with '<' and '>'
set showmatch     " set show matching parenthesis
set ignorecase    " ignore case when searching
set smartcase     " ignore case if search pattern is all lowercase,
                    "    case-sensitive otherwise
set smarttab      " insert tabs on the start of a line according to
                    "    shiftwidth, not tabstop
set nohlsearch      " highlight search terms
set incsearch     " show search matches as you type

set undofile
set number

" tab stuff"
set expandtab

" tab stuff for yaml files"
autocmd FileType yaml setlocal shiftwidth=2 tabstop=2
autocmd FileType yml setlocal shiftwidth=2 tabstop=2

" syntastic options "
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 0
let g:syntastic_python_checkers=['flake8'] " , 'pylint']
" let g:syntastic_python_flake8_args='--ignore=E501,E225,E128'

" set filetypes for certain nonstandard file extensions
autocmd BufNewFile,BufRead *.ts setlocal filetype=typescript
autocmd BufNewFile,BufRead *.j2,*.jinja,*.jinja2 set filetype=jinja

filetype indent plugin on

" fodling stuff"
set foldmethod=indent   
set foldnestmax=10
set foldlevel=20
set foldignore=

" Enable folding with the spacebar
nnoremap <space> za

"split navigations
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

" buffer navigation
map gn :bn<cr>
map gp :bp<cr>
map <leader>bd :bd<cr>
map <leader>qq :qa!<cr>

" flag unneccesary whitespace
highlight BadWhitespace ctermbg=red guibg=darkred
au BufRead,BufNewFile *.py,*.pyw,*.c,*.h match BadWhitespace /\s\+$/

" highlight overlength lines
" highlight Error ctermbg=red ctermfg=white guibg=#592929

colorscheme onedark
