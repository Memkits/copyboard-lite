
{}
  :about "|Machine-generated snapshot. Do not edit directly — changes will be overwritten. Use `calcit query` to inspect and `calcit edit`/`calcit tree` to modify. Run `calcit docs agents --contract` before mutations; use `--full` for first orientation or changed contract digest. Manual edits must follow format and schema conventions, then run `calcit edit format`."
  :package |app
  :entries $ {}
    :default $ {} (:description |) (:init-fn 'app.lite/main!) (:mode :native) (:reload-fn 'app.lite/reload!)
      :feature-policy $ {}
      :modules $ [] |js-ffi/
      :type-slots $ {}
    :server $ {} (:description |) (:init-fn 'app.server/main!) (:mode :native) (:reload-fn 'app.server/reload!)
      :feature-policy $ {}
      :modules $ [] |recollect/ |cumulo-util.calcit/ |cumulo-reel.calcit/ |calcit.std/ |calcit-wss/ |calcit-http/
      :type-slots $ {}
  :files $ {} $ 'app.lite
    %{} 'FileEntry
      :defs $ {}
        '*snippets $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defatom *snippets (empty-snippets-js)
          :examples $ []
          :schema $ :: 'Ref 'JsObject
        'SnippetArrayHost $ %{} 'CodeEntry (:doc |)
          :code $ quote $ deftrait SnippetArrayHost (:length 'Number)
            .for-each! $ :: 'Fn $ {}
              :args $ [] 'app.lite/SnippetArrayHost $ :: 'Fn
                {}
                  :args $ [] 'JsObject 'Number 'JsObject
                  :return 'Unit
              :return 'Unit
            .unshift! $ :: 'Fn $ {}
              :args $ [] 'app.lite/SnippetArrayHost 'JsObject
              :return 'Number
          :examples $ []
          :ffi $ {} (:backend :js) (:kind :external-object) (:target :browser)
            :names $ {} (:for-each! |forEach) (:unshift! |unshift)
          :schema $ :: 'Trait
        'api-base $ %{} 'CodeEntry (:doc |)
          :code $ quote $ def api-base
            let
                location $ browser/location-snapshot
                hostname $ location :hostname
                query $ shared/search-params-create $ location :search
                environment $ option:unwrap-or (shared/search-params-get query |env) |
                local-host? $ or (= hostname |localhost) (= hostname |127.0.0.1)
              if
                and local-host? $ not= environment |prod
                , |http://127.0.0.1:11030 |https://cp.chenyong.life
          :examples $ []
          :schema $ :: 'String
        'auth-headers $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn auth-headers ()
            let
                token $ option:unwrap-or (get-token) |
                headers $ shared/headers-create
              shared/headers-set! headers |Content-Type |application/json
              shared/headers-set! headers |Authorization $ str (shared/decode-uri-component |Bearer%20) token
              , headers
          :examples $ []
          :schema $ :: 'Fn $ {} (:return 'js-ffi.shared/HeadersHost)
            :args $ []
        'checked-snippet-array $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn checked-snippet-array (value)
            if (js/Array.isArray value) (unsafe-coerce value SnippetArrayHost) (raise |Expected-snippets-array)
          :examples $ []
          :schema $ :: 'Fn $ {} (:return 'app.lite/SnippetArrayHost)
            :args $ [] 'JsObject
            :features $ #{} :js-ffi
        'create-snippet! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn create-snippet! (content)
            hint-fn $ {} $ :async true
            try
              let
                  headers $ auth-headers
                  request $ js-await $ shared/fetch-request (str api-base |/api/snippets) (%:: shared/HttpMethod :post) headers
                    %some $ contract/expect-string |body $ js/JSON.stringify
                      js-object $ :content content
                match request
                  (:ok response)
                    if (response :ok?)
                      let
                          created-result $ js-await $ shared/response-json response
                        match created-result
                          (:ok created)
                            let
                                input $ option:unwrap $ browser/query-selector |#content
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
          :schema $ :: 'Fn $ {} (:async true) (:return 'Unit)
            :args $ [] 'String
            :features $ #{} :js-ffi
        'empty-snippets-js $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn empty-snippets-js () (js-array)
          :examples $ []
          :schema $ :: 'Fn $ {} (:return 'JsObject)
            :args $ []
            :features $ #{} :js-ffi
        'get-token $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn get-token () (browser/storage-get |copyboard-lite-token)
          :examples $ []
          :schema $ :: 'Fn $ {}
            :args $ []
            :return $ :: 'calcit.core/Option 'String
        'handle-response-failure! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn handle-response-failure! (status label)
            if (= 401 status) (logout!) (set-status! label |error)
          :examples $ []
          :schema $ :: 'Fn $ {} (:return 'Unit)
            :args $ [] 'Number 'String
        'load-snippets! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn load-snippets! ()
            hint-fn $ {} $ :async true
            try
              let
                  headers $ auth-headers
                  request $ js-await $ shared/fetch-request (str api-base |/api/snippets) (%:: shared/HttpMethod :get) headers (%none)
                match request
                  (:ok response)
                    if (response :ok?)
                      let
                          snippets-result $ js-await $ shared/response-json response
                        match snippets-result
                          (:ok snippets)
                            let
                                username $ option:unwrap-or (browser/storage-get |copyboard-lite-user) |
                              reset! *snippets snippets
                              render-snippets! snippets
                              show-board! username
                              set-status! "|已同步" |online
                          (:err error) (raise error)
                      handle-response-failure! (response :status) "|加载失败"
                  (:err error) (raise error)
              fn (error) (shared/console-error! |Failed-to-load-snippets) (set-status! "|连接失败" |error)
          :examples $ []
          :schema $ :: 'Fn $ {} (:async true) (:return 'Unit)
            :args $ []
            :features $ #{} :js-ffi
        'login! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn login! ()
            hint-fn $ {} $ :async true
            try
              let
                  username-input $ option:unwrap $ browser/query-selector |#username
                  password-input $ option:unwrap $ browser/query-selector |#password
                  username $ option:unwrap-or
                    js-nullish->option $ username-input :value
                    , |
                  password $ option:unwrap-or
                    js-nullish->option $ password-input :value
                    , |
                  headers $ shared/headers-create
                shared/headers-set! headers |Content-Type |application/json
                let
                    request $ js-await $ shared/fetch-request (str api-base |/api/auth/login) (%:: shared/HttpMethod :post) headers
                      %some $ contract/expect-string |body $ js/JSON.stringify
                        js-object (:username username) (:password password)
                  match request
                    (:ok response)
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
          :schema $ :: 'Fn $ {} (:async true) (:return 'Unit)
            :args $ []
            :features $ #{} :js-ffi
        'logout! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn logout! () (browser/storage-remove! |copyboard-lite-token) (browser/storage-remove! |copyboard-lite-user)
            reset! *snippets $ empty-snippets-js
            render-snippets! @*snippets
            show-login!
          :examples $ []
          :schema $ :: 'Fn $ {} (:return 'Unit)
            :args $ []
        'main! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn main! () (wire-events!)
            if
              option:some? $ get-token
              do (set-status! "|验证登录" |online) (load-snippets!)
              show-login!
            println |Copyboard-Lite-started
          :examples $ []
          :schema $ :: 'Fn $ {} (:return 'Unit)
            :args $ []
        'refresh-if-active! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn refresh-if-active! ()
            when
              option:some? $ get-token
              match (browser/visibility-state)
                (:visible) (load-snippets!)
                _ &unit
          :examples $ []
          :schema $ :: 'Fn $ {} (:return 'Unit)
            :args $ []
        'reload! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn reload! ()
            if
              option:some? $ get-token
              load-snippets!
              show-login!
            println |Copyboard-Lite-reloaded
          :examples $ []
          :schema $ :: 'Fn $ {} (:return 'Unit)
            :args $ []
        'remove-snippet! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn remove-snippet! (id)
            hint-fn $ {} $ :async true
            try
              let
                  headers $ auth-headers
                  request $ js-await $ shared/fetch-request (str api-base |/api/snippets/ id) (%:: shared/HttpMethod :delete) headers (%none)
                match request
                  (:ok response)
                    if (response :ok?)
                      js-await $ load-snippets!
                      handle-response-failure! (response :status) "|删除失败"
                  (:err error) (raise error)
              fn (error) (shared/console-error! |Failed-to-remove-snippet) (set-status! "|删除失败" |error)
          :examples $ []
          :schema $ :: 'Fn $ {} (:async true) (:return 'Unit)
            :args $ [] 'Number
            :features $ #{} :js-ffi
        'render-snippets! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn render-snippets! (snippets)
            let
                container $ option:unwrap $ browser/query-selector |#snippets
                empty-node $ option:unwrap $ browser/query-selector |#empty
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
          :schema $ :: 'Fn $ {} (:return 'Unit)
            :args $ [] 'JsObject
            :features $ #{} :js-ffi
        'set-status! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn set-status! (label state)
            let
                target $ option:unwrap $ browser/query-selector |#status
              browser/element-set-text-content! target label
              browser/element-set-class-name! target $ str |status | state
          :examples $ []
          :schema $ :: 'Fn $ {} (:return 'Unit)
            :args $ [] 'String 'String
        'show-board! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn show-board! (username)
            let
                login-panel $ option:unwrap $ browser/query-selector |#login-panel
                board $ option:unwrap $ browser/query-selector |#board
                current-user $ option:unwrap $ browser/query-selector |#current-user
                input $ option:unwrap $ browser/query-selector |#content
              browser/element-set-hidden! login-panel true
              browser/element-set-hidden! board false
              browser/element-set-text-content! current-user username
              browser/element-focus! input
          :examples $ []
          :schema $ :: 'Fn $ {} (:return 'Unit)
            :args $ [] 'String
        'show-login! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn show-login! ()
            let
                login-panel $ option:unwrap $ browser/query-selector |#login-panel
                board $ option:unwrap $ browser/query-selector |#board
              browser/element-set-hidden! login-panel false
              browser/element-set-hidden! board true
              set-status! "|请登录" |
          :examples $ []
          :schema $ :: 'Fn $ {} (:return 'Unit)
            :args $ []
        'submit-content! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn submit-content! ()
            let
                input $ option:unwrap $ browser/query-selector |#content
                content $ option:unwrap-or
                  js-nullish->option $ input :value
                  , |
              when
                > (count content) 0
                do (set-status! "|保存中" |online) (create-snippet! content)
              , &unit
          :examples $ []
          :schema $ :: 'Fn $ {} (:return 'Unit)
            :args $ []
            :features $ #{} :js-ffi
        'wire-events! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn wire-events! ()
            let
                login-form $ option:unwrap $ browser/query-selector |#login-form
                form $ option:unwrap $ browser/query-selector |#snippet-form
                input $ option:unwrap $ browser/query-selector |#content
                refresh $ option:unwrap $ browser/query-selector |#refresh
                logout-button $ option:unwrap $ browser/query-selector |#logout
                document-element $ browser/element-host js/document
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
              browser/element-add-event-listener! document-element |visibilitychange $ fn (_event) (refresh-if-active!)
              browser/add-event-listener! |focus $ fn (_event) (refresh-if-active!)
              browser/add-event-listener! |online $ fn (_event) (refresh-if-active!)
          :examples $ []
          :schema $ :: 'Fn $ {} (:return 'Unit)
            :args $ []
            :features $ #{} :js-ffi
      :ns $ %{} 'NsEntry (:doc |)
        :code $ quote $ ns app.lite
          :require (js-ffi.browser :as browser) (js-ffi.shared :as shared) (js-ffi.contract :as contract)
