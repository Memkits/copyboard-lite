
{}
  :about "|Machine-generated snapshot. Do not edit directly — changes will be overwritten. Use `calcit query` to inspect and `calcit edit`/`calcit tree` to modify. Run `calcit docs agents --contract` before mutations; use `--full` for first orientation or changed contract digest. Manual edits must follow format and schema conventions, then run `calcit edit format`."
  :package |app
  :entries $ {} $ :default
    {} (:description |) (:init-fn 'app.lite/main!) (:mode :js) (:reload-fn 'app.lite/reload!) (:target :browser)
      :feature-policy $ {}
      :modules $ [] |js-ffi/
      :type-slots $ {}
  :files $ {} $ 'app.lite
    %{} 'FileEntry
      :defs $ {}
        '*snippets $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defref *snippets (empty-snippets-js)
          :examples $ []
          :schema $ quote $ Ref JsObject
        'SnippetArrayHost $ %{} 'CodeEntry (:doc |)
          :code $ quote $ deftrait SnippetArrayHost (:length 'Number)
            .for-each! $ quote $ Fn app.lite/SnippetArrayHost
              Fn JsObject Number JsObject $ -> Unit
              -> Unit
            .unshift! $ quote $ Fn app.lite/SnippetArrayHost JsObject (-> Number)
          :examples $ []
          :ffi $ {} (:backend :js) (:kind :external-object) (:target :browser)
            :names $ {} (:for-each! |forEach) (:unshift! |unshift)
          :schema $ quote Trait
        'api-base $ %{} 'CodeEntry (:doc |)
          :code $ quote $ def api-base
            let
                location $ browser/location-snapshot
                hostname $ location :hostname
                query $ shared/search-params-create $ location :search
                environment $ .unwrap-or (shared/search-params-get query |env) |
                local-host? $ or (= hostname |localhost) (= hostname |127.0.0.1)
              if
                and local-host? $ not= environment |prod
                , |http://127.0.0.1:11030 |https://cp.chenyong.life
          :examples $ []
          :schema $ quote String
        'auth-headers $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn auth-headers ()
            let
                token $ .unwrap-or (get-token) |
                headers $ shared/headers-create
              shared/headers-set! headers |Content-Type |application/json
              shared/headers-set! headers |Authorization $ str (shared/decode-uri-component |Bearer%20) token
              , headers
          :examples $ []
          :schema $ quote $ Fn (-> js-ffi.shared/HeadersHost)
        'checked-snippet-array $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn checked-snippet-array (value)
            if (js/Array.isArray value) (js-cast value 'app.lite/SnippetArrayHost) (raise |Expected-snippets-array)
          :examples $ []
          :schema $ quote $ Fn JsObject (-> app.lite/SnippetArrayHost) (:features :js-ffi)
        'create-snippet! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn create-snippet! (content) (hint-fn Async)
            try
              let
                  headers $ auth-headers
                  request $ js-await $ shared/fetch-request (str api-base |/api/snippets) (%:: shared/HttpMethod :post) headers
                    Option :some $ contract/expect-string |body $ js/JSON.stringify
                      js-object $ :content content
                match request
                  (:ok response)
                    do
                      store-renewed-token! $ shared/headers-get (response :headers) |x-copyboard-token
                      if (response :ok?)
                        let
                            created-result $ js-await $ shared/response-json response
                          match created-result
                            (:ok created)
                              let
                                  input $ .unwrap $ browser/query-selector |#content
                                let
                                    snippet-array $ checked-snippet-array @*snippets
                                  snippet-array .unshift! created
                                render-snippets! @*snippets
                                browser/element-set-value! input |
                                browser/element-focus! input
                                set-status! "|已保存" |online
                            (:err error) (raise error)
                        handle-response-failure! (response :status) "|保存失败"
                  (:err error) (raise error)
              fn (error) (shared/console-error! |Failed-to-create-snippet) (set-status! "|保存失败" |error)
          :examples $ []
          :schema $ quote $ Fn String (-> Unit) (:features :js-ffi) (:async)
        'empty-snippets-js $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn empty-snippets-js () (js-array)
          :examples $ []
          :schema $ quote $ Fn (-> JsObject) (:features :js-ffi)
        'get-token $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn get-token () (browser/storage-get |copyboard-lite-token)
          :examples $ []
          :schema $ quote $ Fn
            -> $ calcit.core/Option String
        'handle-response-failure! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn handle-response-failure! (status label)
            if (= 401 status) (logout!) (set-status! label |error)
          :examples $ []
          :schema $ quote $ Fn Number String (-> Unit)
        'link-href $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn link-href (content)
            let
                candidate $ content .trim
              if
                and
                  or (candidate .starts-with? |https://) (candidate .starts-with? |http://)
                  not $ candidate .includes? "| "
                  not $ candidate .includes? "|\t"
                  = 1 $ .len $ candidate .split-lines
                try
                  let
                      url $ shared/url-snapshot $ shared/url-create candidate candidate
                    if
                      and
                        not= | $ url :host
                        or
                          = |https: $ url :protocol
                          = |http: $ url :protocol
                      Option :some $ url :href
                      Option :none
                  fn (_error) (Option :none)
                Option :none
          :examples $ []
          :schema $ quote $ Fn String
            -> $ Option String
            :features :js-ffi
        'load-snippets! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn load-snippets! () (hint-fn Async)
            try
              let
                  headers $ auth-headers
                  request $ js-await $ shared/fetch-request (str api-base |/api/snippets) (%:: shared/HttpMethod :get) headers (Option :none)
                match request
                  (:ok response)
                    do
                      store-renewed-token! $ shared/headers-get (response :headers) |x-copyboard-token
                      if (response :ok?)
                        let
                            snippets-result $ js-await $ shared/response-json response
                          match snippets-result
                            (:ok snippets)
                              let
                                  username $ .unwrap-or (browser/storage-get |copyboard-lite-user) |
                                reset! *snippets snippets
                                render-snippets! snippets
                                show-board! username
                                set-status! "|已同步" |online
                            (:err error) (raise error)
                        handle-response-failure! (response :status) "|加载失败"
                  (:err error) (raise error)
              fn (error) (shared/console-error! |Failed-to-load-snippets) (set-status! "|连接失败" |error)
          :examples $ []
          :schema $ quote $ Fn (-> Unit) (:features :js-ffi) (:async)
        'login! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn login! () (hint-fn Async)
            try
              let
                  username-input $ .unwrap $ browser/query-selector |#username
                  password-input $ .unwrap $ browser/query-selector |#password
                  username $ browser/element-value username-input
                  password $ browser/element-value password-input
                  headers $ shared/headers-create
                shared/headers-set! headers |Content-Type |application/json
                let
                    request $ js-await $ shared/fetch-request (str api-base |/api/auth/login) (%:: shared/HttpMethod :post) headers
                      Option :some $ contract/expect-string |body $ js/JSON.stringify
                        js-object (:username username) (:password password)
                  match request
                    (:ok response)
                      do
                        store-renewed-token! $ shared/headers-get (response :headers) |x-copyboard-token
                        if (response :ok?)
                          let
                              data-result $ js-await $ shared/response-json response
                            match data-result
                              (:ok data)
                                let
                                    token $ contract/expect-string |token $ contract/object-field |login-response data |token
                                    user $ contract/expect-string |username $ contract/object-field |login-response data |username
                                  browser/storage-set! |copyboard-lite-token token
                                  browser/storage-set! |copyboard-lite-user user
                                  browser/element-set-value! password-input |
                                  set-status! "|正在同步" |online
                                  js-await $ load-snippets!
                              (:err error) (raise error)
                          do (logout!) (set-status! "|登录失败" |error)
                    (:err error) (raise error)
              fn (error) (shared/console-error! |Failed-to-login) (set-status! "|登录失败" |error)
          :examples $ []
          :schema $ quote $ Fn (-> Unit) (:features :js-ffi) (:async)
        'logout! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn logout! () (browser/storage-remove! |copyboard-lite-token) (browser/storage-remove! |copyboard-lite-user)
            reset! *snippets $ empty-snippets-js
            render-snippets! @*snippets
            show-login!
          :examples $ []
          :schema $ quote $ Fn (-> Unit)
        'main! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn main! () (wire-events!)
            if
              .some? $ get-token
              do (set-status! "|验证登录" |online) (load-snippets!)
              show-login!
            println |Copyboard-Lite-started
          :examples $ []
          :schema $ quote $ Fn (-> Unit)
        'refresh-if-active! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn refresh-if-active! ()
            when
              .some? $ get-token
              match (browser/visibility-state)
                (:visible) (load-snippets!)
                _ &unit
            , &unit
          :examples $ []
          :schema $ quote $ Fn (-> Unit)
        'reload! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn reload! ()
            if
              .some? $ get-token
              load-snippets!
              show-login!
            println |Copyboard-Lite-reloaded
          :examples $ []
          :schema $ quote $ Fn (-> Unit)
        'remove-snippet! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn remove-snippet! (id) (hint-fn Async)
            try
              let
                  headers $ auth-headers
                  request $ js-await $ shared/fetch-request (str api-base |/api/snippets/ id) (%:: shared/HttpMethod :delete) headers (Option :none)
                match request
                  (:ok response)
                    do
                      store-renewed-token! $ shared/headers-get (response :headers) |x-copyboard-token
                      if (response :ok?)
                        js-await $ load-snippets!
                        handle-response-failure! (response :status) "|删除失败"
                  (:err error) (raise error)
              fn (error) (shared/console-error! |Failed-to-remove-snippet) (set-status! "|删除失败" |error)
          :examples $ []
          :schema $ quote $ Fn Number (-> Unit) (:features :js-ffi) (:async)
        'render-snippets! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn render-snippets! (snippets)
            let
                container $ .unwrap $ browser/query-selector |#snippets
                empty-node $ .unwrap $ browser/query-selector |#empty
                snippet-array $ checked-snippet-array snippets
              browser/element-set-inner-html! container |
              browser/element-set-hidden! empty-node $ not= 0 $ snippet-array :length
              snippet-array .for-each! $ fn (raw-snippet _index _array)
                let
                    snippet $ contract/expect-object |snippet raw-snippet
                    content $ contract/expect-string |content $ contract/object-field |snippet snippet |content
                    id $ contract/expect-number |id $ contract/object-field |snippet snippet |id
                    created-at $ contract/expect-number |created_at $ contract/object-field |snippet snippet |created_at
                    card $ browser/create-element |article
                    text-node $ browser/create-element |p
                    actions $ browser/create-element |div
                    time-node $ browser/create-element |time
                    copy-button $ browser/create-element |button
                    remove-button $ browser/create-element |button
                  browser/element-set-class-name! card |snippet
                  let
                      link $ link-href content
                    if (.some? link)
                      let
                          anchor $ browser/create-element |a
                        browser/element-set-text-content! anchor content
                        browser/element-set-attribute! anchor |href $ .unwrap link
                        browser/element-set-attribute! anchor |target |_blank
                        browser/element-set-attribute! anchor |rel "|noopener noreferrer"
                        browser/append-child! text-node anchor
                      browser/element-set-text-content! text-node content
                  browser/element-set-class-name! actions |snippet-actions
                  browser/element-set-text-content! time-node $ shared/date-local-string $ shared/date-from-ms created-at
                  browser/element-set-text-content! copy-button "|复制"
                  browser/element-set-attribute! copy-button |type |button
                  browser/element-set-attribute! copy-button |aria-label "|复制内容"
                  browser/element-set-attribute! copy-button |title "|复制内容"
                  browser/element-set-text-content! remove-button "|删除"
                  browser/element-set-attribute! remove-button |type |button
                  browser/element-set-attribute! remove-button |aria-label "|删除内容"
                  browser/element-set-attribute! remove-button |title "|删除内容"
                  browser/element-set-class-name! remove-button |remove
                  browser/element-add-event-listener! copy-button |click $ fn (_event) (browser/clipboard-write-text! content)
                  browser/element-add-event-listener! remove-button |click $ fn (_event) (remove-snippet! id) &unit
                  browser/append-child! actions time-node
                  browser/append-child! actions copy-button
                  browser/append-child! actions remove-button
                  browser/append-child! card text-node
                  browser/append-child! card actions
                  browser/append-child! container card
                  , &unit
          :examples $ []
          :schema $ quote $ Fn JsObject (-> Unit) (:features :js-ffi)
        'set-status! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn set-status! (label state)
            let
                target $ .unwrap $ browser/query-selector |#status
              browser/element-set-text-content! target label
              browser/element-set-class-name! target $ str |status | state
          :examples $ []
          :schema $ quote $ Fn String String (-> Unit)
        'show-board! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn show-board! (username)
            let
                login-panel $ .unwrap $ browser/query-selector |#login-panel
                board $ .unwrap $ browser/query-selector |#board
                current-user $ .unwrap $ browser/query-selector |#current-user
                input $ .unwrap $ browser/query-selector |#content
              browser/element-set-hidden! login-panel true
              browser/element-set-hidden! board false
              browser/element-set-text-content! current-user username
              browser/element-focus! input
          :examples $ []
          :schema $ quote $ Fn String (-> Unit)
        'show-login! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn show-login! ()
            let
                login-panel $ .unwrap $ browser/query-selector |#login-panel
                board $ .unwrap $ browser/query-selector |#board
              browser/element-set-hidden! login-panel false
              browser/element-set-hidden! board true
              set-status! "|请登录" |
          :examples $ []
          :schema $ quote $ Fn (-> Unit)
        'store-renewed-token! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn store-renewed-token! (token)
            when (.some? token)
              browser/storage-set! |copyboard-lite-token $ .unwrap token
            , &unit
          :examples $ []
          :schema $ quote $ Fn (Option String) (-> Unit)
        'submit-content! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn submit-content! ()
            let
                input $ .unwrap $ browser/query-selector |#content
                content $ browser/element-value input
              when
                > (.len content) 0
                do (set-status! "|保存中" |online) (create-snippet! content)
              , &unit
          :examples $ []
          :schema $ quote $ Fn (-> Unit) (:features :js-ffi)
        'wire-events! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn wire-events! ()
            let
                login-form $ .unwrap $ browser/query-selector |#login-form
                form $ .unwrap $ browser/query-selector |#snippet-form
                input $ .unwrap $ browser/query-selector |#content
                refresh $ .unwrap $ browser/query-selector |#refresh
                logout-button $ .unwrap $ browser/query-selector |#logout
              browser/element-add-event-listener! login-form |submit $ fn (event) (event .prevent-default!) (login!) &unit
              browser/element-add-event-listener! form |submit $ fn (event) (event .prevent-default!) (submit-content!)
              browser/element-add-event-listener! input |keydown $ fn (event)
                let
                    key-event $ browser/keyboard-event-host event
                  when
                    and
                      = |Enter $ key-event :key
                      or (key-event :meta-key?) (key-event :ctrl-key?)
                    do (key-event .prevent-default!) (submit-content!)
                , &unit
              browser/element-add-event-listener! refresh |click $ fn (_event) (set-status! "|刷新中" |online) (load-snippets!) &unit
              browser/element-add-event-listener! logout-button |click $ fn (_event) (logout!)
              browser/document-add-event-listener! |visibilitychange $ fn (_event) (refresh-if-active!)
              browser/add-event-listener! |focus $ fn (_event) (refresh-if-active!)
              browser/add-event-listener! |online $ fn (_event) (refresh-if-active!)
          :examples $ []
          :schema $ quote $ Fn (-> Unit) (:features :js-ffi)
      :ns $ %{} 'NsEntry (:doc |)
        :code $ quote $ ns app.lite
          :require (js-ffi.browser :as browser) (js-ffi.shared :as shared) (js-ffi.contract :as contract)
