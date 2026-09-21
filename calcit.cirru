
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
          :code $ quote $ defatom *snippets (js-array)
          :examples $ []
          :schema $ :: 'Dynamic
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
          :schema $ :: 'Dynamic
        'auth-headers $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn auth-headers ()
            let
                token $ option:unwrap-or (get-token) |
                headers $ shared/headers-create
              shared/headers-set! headers |Content-Type |application/json
              shared/headers-set! headers |Authorization $ str (shared/decode-uri-component |Bearer%20) token
              , headers
          :examples $ []
          :schema $ :: 'Dynamic
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
                              .!unshift @*snippets created
                              render-snippets! @*snippets
                              browser/element-set-value! input |
                              browser/element-focus! input
                              set-status! "|已保存" |online
                          (:err error) (raise error)
                      handle-response-failure! (response :status) "|保存失败"
                  (:err error) (raise error)
              fn (error)
                do (shared/console-error! |Failed-to-create-snippet) (set-status! "|保存失败" |error)
          :examples $ []
          :schema $ :: 'Dynamic
        'get-token $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn get-token () (browser/storage-get |copyboard-lite-token)
          :examples $ []
          :schema $ :: 'Dynamic
        'handle-response-failure! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn handle-response-failure! (status label)
            if (= 401 status) (logout!) (set-status! label |error)
          :examples $ []
          :schema $ :: 'Dynamic
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
              fn (error)
                do (shared/console-error! |Failed-to-load-snippets) (set-status! "|连接失败" |error)
          :examples $ []
          :schema $ :: 'Dynamic
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
              fn (error)
                do (shared/console-error! |Failed-to-login) (set-status! "|登录失败" |error)
          :examples $ []
          :schema $ :: 'Dynamic
        'logout! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn logout! () (browser/storage-remove! |copyboard-lite-token) (browser/storage-remove! |copyboard-lite-user)
            reset! *snippets $ js-array
            render-snippets! @*snippets
            show-login!
          :examples $ []
          :schema $ :: 'Dynamic
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
                _ nil
          :examples $ []
          :schema $ :: 'Dynamic
        'reload! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn reload! ()
            if
              option:some? $ get-token
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
                  headers $ auth-headers
                  request $ js-await $ shared/fetch-request (str api-base |/api/snippets/ id) (%:: shared/HttpMethod :delete) headers (%none)
                match request
                  (:ok response)
                    if (response :ok?)
                      js-await $ load-snippets!
                      handle-response-failure! (response :status) "|删除失败"
                  (:err error) (raise error)
              fn (error)
                do (shared/console-error! |Failed-to-remove-snippet) (set-status! "|删除失败" |error)
          :examples $ []
          :schema $ :: 'Dynamic
        'render-snippets! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn render-snippets! (snippets)
            let
                container $ option:unwrap $ browser/query-selector |#snippets
                empty-node $ option:unwrap $ browser/query-selector |#empty
              browser/element-set-inner-html! container |
              browser/element-set-hidden! empty-node $ not= 0 $ unsafe-coerce (.-length snippets) Number
              .!forEach snippets $ fn (raw-snippet & _index)
                let
                    snippet $ unsafe-coerce raw-snippet JsObject
                    content $ unsafe-coerce (.-content snippet) String
                    id $ unsafe-coerce (.-id snippet) Number
                    created-at $ unsafe-coerce (.-created_at snippet) Number
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
                  do (browser/element-set-attribute! copy-button |type |button) (browser/element-set-attribute! copy-button |aria-label "|复制内容") (browser/element-set-attribute! copy-button |title "|复制内容")
                  browser/element-set-text-content! remove-button "|删除"
                  do (browser/element-set-attribute! remove-button |type |button) (browser/element-set-attribute! remove-button |aria-label "|删除内容") (browser/element-set-attribute! remove-button |title "|删除内容")
                  browser/element-set-class-name! remove-button |remove
                  browser/element-add-event-listener! copy-button |click $ fn (_event) (browser/clipboard-write-text! content)
                  browser/element-add-event-listener! remove-button |click $ fn (_event) (remove-snippet! id)
                  browser/append-child! actions time-node
                  browser/append-child! actions copy-button
                  browser/append-child! actions remove-button
                  browser/append-child! card text-node
                  browser/append-child! card actions
                  browser/append-child! container card
          :examples $ []
          :schema $ :: 'Dynamic
        'set-status! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn set-status! (label state)
            let
                target $ option:unwrap $ browser/query-selector |#status
              browser/element-set-text-content! target label
              browser/element-set-class-name! target $ str |status | state
          :examples $ []
          :schema $ :: 'Dynamic
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
          :schema $ :: 'Dynamic
        'show-login! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn show-login! ()
            let
                login-panel $ option:unwrap $ browser/query-selector |#login-panel
                board $ option:unwrap $ browser/query-selector |#board
              browser/element-set-hidden! login-panel false
              browser/element-set-hidden! board true
              set-status! "|请登录" |
          :examples $ []
          :schema $ :: 'Dynamic
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
          :examples $ []
          :schema $ :: 'Dynamic
        'wire-events! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn wire-events! ()
            let
                login-form $ option:unwrap $ browser/query-selector |#login-form
                form $ option:unwrap $ browser/query-selector |#snippet-form
                input $ option:unwrap $ browser/query-selector |#content
                refresh $ option:unwrap $ browser/query-selector |#refresh
                logout-button $ option:unwrap $ browser/query-selector |#logout
                document-element $ browser/element-host js/document
              browser/element-add-event-listener! login-form |submit $ fn (event)
                do (event .prevent-default!) (login!)
              browser/element-add-event-listener! form |submit $ fn (event)
                do (event .prevent-default!) (submit-content!)
              browser/element-add-event-listener! input |keydown $ fn (event)
                let
                    key-event $ browser/keyboard-event-host event
                  when
                    and
                      = |Enter $ key-event :key
                      or (key-event :meta-key?) (key-event :ctrl-key?)
                    do (key-event .prevent-default!) (submit-content!)
              browser/element-add-event-listener! refresh |click $ fn (_event)
                do (set-status! "|刷新中" |online) (load-snippets!)
              browser/element-add-event-listener! logout-button |click $ fn (_event) (logout!)
              browser/element-add-event-listener! document-element |visibilitychange $ fn (_event) (refresh-if-active!)
              browser/add-event-listener! |focus $ fn (_event) (refresh-if-active!)
              browser/add-event-listener! |online $ fn (_event) (refresh-if-active!)
          :examples $ []
          :schema $ :: 'Dynamic
      :ns $ %{} 'NsEntry (:doc |)
        :code $ quote $ ns app.lite
          :require (js-ffi.browser :as browser) (js-ffi.shared :as shared) (js-ffi.contract :as contract)
