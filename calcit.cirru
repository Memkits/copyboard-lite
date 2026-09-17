
{}
  :about "|Machine-generated snapshot. Do not edit directly — changes will be overwritten. Use `calcit query` to inspect and `calcit edit`/`calcit tree` to modify. Run `calcit docs agents --contract` before mutations; use `--full` for first orientation or changed contract digest. Manual edits must follow format and schema conventions, then run `calcit edit format`."
  :package |app
  :entries $ {}
    :default $ {} (:description |) (:init-fn 'app.lite/main!) (:mode :native) (:reload-fn 'app.lite/reload!)
      :feature-policy $ {}
      :modules $ []
      :type-slots $ {}
    :server $ {} (:description |) (:init-fn 'app.server/main!) (:mode :native) (:reload-fn 'app.server/reload!)
      :feature-policy $ {}
      :modules $ [] |recollect/ |cumulo-util.calcit/ |cumulo-reel.calcit/ |calcit.std/ |calcit-wss/ |calcit-http/
      :type-slots $ {}
  :files $ {} $ 'app.lite
    %{} 'FileEntry
      :defs $ {}
        '*snippets $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defatom *snippets (js-array)
          :examples $ []
          :schema $ :: 'Dynamic
        'api-base $ %{} 'CodeEntry (:doc |)
          :code $ quote $ def api-base
            let
                browser-location $ unsafe-coerce js/location JsObject
                hostname $ unsafe-coerce (.-hostname browser-location) String
                query $ new js/URLSearchParams $ .-search browser-location
                environment $ unsafe-coerce (.!get query |env) String
                local-host? $ or (= hostname |localhost) (= hostname |127.0.0.1)
              if
                and local-host? $ not= environment |prod
                , |http://127.0.0.1:11030 |https://cp.chenyong.life
          :examples $ []
          :schema $ :: 'Dynamic
        'auth-headers $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn auth-headers ()
            let
                token $ unsafe-coerce (get-token) String
              js-object (|Content-Type |application/json)
                |Authorization $ str (js/decodeURIComponent |Bearer%20) token
          :examples $ []
          :schema $ :: 'Dynamic
        'create-snippet! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn create-snippet! (content)
            hint-fn $ {} $ :async true
            try
              let
                  response $ js-await $ js/fetch (str api-base |/api/snippets)
                    js-object (:method |POST)
                      :headers $ auth-headers
                      :body $ js/JSON.stringify $ js-object (:content content)
                if (.-ok response)
                  let
                      created $ js-await $ .!json response
                      input $ unsafe-coerce (js/document.querySelector |#content) JsObject
                    .!unshift @*snippets created
                    render-snippets! @*snippets
                    set! (.-value input) |
                    .!focus input
                    set-status! "|已保存" |online
                  logout!
              fn (error)
                do (js/console.error |Failed-to-create-snippet error) (set-status! "|保存失败" |error)
          :examples $ []
          :schema $ :: 'Dynamic
        'get-token $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn get-token () (js/localStorage.getItem |copyboard-lite-token)
          :examples $ []
          :schema $ :: 'Dynamic
        'load-snippets! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn load-snippets! ()
            hint-fn $ {} $ :async true
            try
              let
                  response $ js-await $ js/fetch (str api-base |/api/snippets)
                    js-object $ :headers $ auth-headers
                if (.-ok response)
                  let
                      snippets $ js-await $ .!json response
                    reset! *snippets snippets
                    render-snippets! snippets
                    set-status! "|已连接" |online
                  logout!
              fn (error)
                do (js/console.error |Failed-to-load-snippets error) (set-status! "|连接失败" |error)
          :examples $ []
          :schema $ :: 'Dynamic
        'login! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn login! ()
            hint-fn $ {} $ :async true
            try
              let
                  username-input $ unsafe-coerce (js/document.querySelector |#username) JsObject
                  password-input $ unsafe-coerce (js/document.querySelector |#password) JsObject
                  username $ unsafe-coerce (.-value username-input) String
                  password $ unsafe-coerce (.-value password-input) String
                  response $ js-await $ js/fetch (str api-base |/api/auth/login)
                    js-object (:method |POST)
                      :headers $ js-object $ |Content-Type |application/json
                      :body $ js/JSON.stringify $ js-object (:username username) (:password password)
                  data $ js-await $ .!json response
                if (.-ok response)
                  let
                      token $ unsafe-coerce (.-token data) String
                      user $ unsafe-coerce (.-username data) String
                    js/localStorage.setItem |copyboard-lite-token token
                    js/localStorage.setItem |copyboard-lite-user user
                    set! (.-value password-input) |
                    show-board! user
                    js-await $ load-snippets!
                  set-status! "|登录失败" |error
              fn (error)
                do (js/console.error |Failed-to-login error) (set-status! "|登录失败" |error)
          :examples $ []
          :schema $ :: 'Dynamic
        'logout! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn logout! () (js/localStorage.removeItem |copyboard-lite-token) (js/localStorage.removeItem |copyboard-lite-user)
            reset! *snippets $ js-array
            render-snippets! @*snippets
            show-login!
          :examples $ []
          :schema $ :: 'Dynamic
        'main! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn main! () (wire-events!)
            if
              js-present? $ get-token
              let
                  username $ unsafe-coerce (js/localStorage.getItem |copyboard-lite-user) String
                show-board! username
                load-snippets!
              show-login!
            println |Copyboard-Lite-started
          :examples $ []
          :schema $ :: 'Dynamic
        'reload! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn reload! ()
            if
              js-present? $ get-token
              load-snippets!
              show-login!
            println |Copyboard-Lite-reloaded
          :examples $ []
          :schema $ :: 'Dynamic
        'remove-snippet! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn remove-snippet! (id)
            hint-fn $ {} $ :async true
            try
              let
                  response $ js-await $ js/fetch (str api-base |/api/snippets/ id)
                    js-object (:method |DELETE)
                      :headers $ auth-headers
                if (.-ok response)
                  js-await $ load-snippets!
                  raise |Failed-to-remove-snippet
              fn (error)
                do (js/console.error |Failed-to-remove-snippet error) (set-status! "|删除失败" |error)
          :examples $ []
          :schema $ :: 'Dynamic
        'render-snippets! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn render-snippets! (snippets)
            let
                container $ unsafe-coerce (js/document.querySelector |#snippets) JsObject
                empty-node $ unsafe-coerce (js/document.querySelector |#empty) JsObject
              set! (.-innerHTML container) |
              set! (.-hidden empty-node)
                not= 0 $ unsafe-coerce (.-length snippets) Number
              .!forEach snippets $ fn (raw-snippet & _index)
                let
                    snippet $ unsafe-coerce raw-snippet JsObject
                    content $ unsafe-coerce (.-content snippet) String
                    id $ unsafe-coerce (.-id snippet) Number
                    created-at $ unsafe-coerce (.-created_at snippet) Number
                    card $ unsafe-coerce (js/document.createElement |article) JsObject
                    text-node $ unsafe-coerce (js/document.createElement |p) JsObject
                    actions $ unsafe-coerce (js/document.createElement |div) JsObject
                    time-node $ unsafe-coerce (js/document.createElement |time) JsObject
                    copy-button $ unsafe-coerce (js/document.createElement |button) JsObject
                    remove-button $ unsafe-coerce (js/document.createElement |button) JsObject
                  set! (.-className card) |snippet
                  set! (.-textContent text-node) content
                  set! (.-className actions) |snippet-actions
                  set! (.-textContent time-node)
                    .!toLocaleString $ new js/Date created-at
                  set! (.-textContent copy-button) "|复制"
                  set! (.-textContent remove-button) "|删除"
                  set! (.-className remove-button) |remove
                  .!addEventListener copy-button |click $ fn (_event)
                    let
                        clipboard $ unsafe-coerce js/navigator.clipboard JsObject
                      .!writeText clipboard content
                  .!addEventListener remove-button |click $ fn (_event) (remove-snippet! id)
                  .!appendChild actions time-node
                  .!appendChild actions copy-button
                  .!appendChild actions remove-button
                  .!appendChild card text-node
                  .!appendChild card actions
                  .!appendChild container card
          :examples $ []
          :schema $ :: 'Dynamic
        'set-status! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn set-status! (label state)
            let
                target $ unsafe-coerce (js/document.querySelector |#status) JsObject
              set! (.-textContent target) label
              set! (.-className target) (str |status | state)
          :examples $ []
          :schema $ :: 'Dynamic
        'show-board! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn show-board! (username)
            let
                login-panel $ unsafe-coerce (js/document.querySelector |#login-panel) JsObject
                board $ unsafe-coerce (js/document.querySelector |#board) JsObject
                current-user $ unsafe-coerce (js/document.querySelector |#current-user) JsObject
                input $ unsafe-coerce (js/document.querySelector |#content) JsObject
              set! (.-hidden login-panel) true
              set! (.-hidden board) false
              set! (.-textContent current-user) username
              .!focus input
          :examples $ []
          :schema $ :: 'Dynamic
        'show-login! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn show-login! ()
            let
                login-panel $ unsafe-coerce (js/document.querySelector |#login-panel) JsObject
                board $ unsafe-coerce (js/document.querySelector |#board) JsObject
              set! (.-hidden login-panel) false
              set! (.-hidden board) true
              set-status! "|请登录" |
          :examples $ []
          :schema $ :: 'Dynamic
        'submit-content! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn submit-content! ()
            let
                input $ unsafe-coerce (js/document.querySelector |#content) JsObject
                content $ unsafe-coerce (.-value input) String
              when
                >
                  unsafe-coerce (.-length content) Number
                  , 0
                do (set-status! "|保存中" |online) (create-snippet! content)
          :examples $ []
          :schema $ :: 'Dynamic
        'wire-events! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn wire-events! ()
            let
                login-form $ unsafe-coerce (js/document.querySelector |#login-form) JsObject
                form $ unsafe-coerce (js/document.querySelector |#snippet-form) JsObject
                input $ unsafe-coerce (js/document.querySelector |#content) JsObject
                refresh $ unsafe-coerce (js/document.querySelector |#refresh) JsObject
                logout-button $ unsafe-coerce (js/document.querySelector |#logout) JsObject
              .!addEventListener login-form |submit $ fn (event)
                do (.!preventDefault event) (login!)
              .!addEventListener form |submit $ fn (event)
                do (.!preventDefault event) (submit-content!)
              .!addEventListener input |keydown $ fn (event)
                when
                  and
                    = |Enter $ unsafe-coerce (.-key event) String
                    or
                      unsafe-coerce (.-metaKey event) Bool
                      unsafe-coerce (.-ctrlKey event) Bool
                  do (.!preventDefault event) (submit-content!)
              .!addEventListener refresh |click $ fn (_event) (load-snippets!)
              .!addEventListener logout-button |click $ fn (_event) (logout!)
          :examples $ []
          :schema $ :: 'Dynamic
      :ns $ %{} 'NsEntry (:doc |)
        :code $ quote $ ns app.lite
