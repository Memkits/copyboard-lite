
{}
  :about "|Machine-generated snapshot. Do not edit directly — changes will be overwritten. Use `calcit query` to inspect and `calcit edit`/`calcit tree` to modify. Run `calcit docs agents --contract` before mutations; use `--full` for first orientation or changed contract digest. Manual edits must follow format and schema conventions, then run `calcit edit format`."
  :package |app
  :entries $ {} $ :default
    {} (:description |) (:init-fn 'app.lite/main!) (:mode :js) (:reload-fn 'app.lite/reload!) (:target :browser)
      :feature-policy $ {}
      :modules $ [] |js-ffi/ |respo-router.calcit/ |respo.calcit/ |respo-ui.calcit/
      :type-slots $ {} $ :dispatch-op |app.schema/Op
  :files $ {}
    'app.comp $ %{} 'FileEntry
      :defs $ {}
        'comp-board $ %{} 'CodeEntry
          :doc "|Signed-in board: account bar, composer, and the snippet list."
          :code $ quote $ defcomp comp-board (store)
            let
                snippets $ :snippets store
                expanded $ :expanded store
              create-element :section
                {} $ :class-name |board
                div
                  {} $ :class-name |user-bar
                  span
                    {} $ :class-name |account-label
                    strong $ {} $ :inner-text (:user store)
                  comp-button "|退出登录" $ opts ButtonOptions :class-name |btn-sm :on-click $ dispatch-fn (_e d!)
                    d! $ :: :logout
                div
                  {} $ :class-name |composer
                  textarea $ {} (:id |content) (:rows 2)
                    :value $ :draft store
                    :placeholder "|粘贴文字或链接…"
                    :class-name $ str-spaced css/textarea |composer-input
                    :aria-label "|添加到剪贴板"
                    :on-input $ fn (e d!)
                      d! $ :: :draft $ event-value e
                    :on-keydown $ fn (e d!)
                      let
                          info $ keyboard-info e
                        when
                          and
                            = |Enter $ :key info
                            or (:meta? info) (:ctrl? info)
                          d! $ :: :submit
                  div
                    {} $ :class-name |composer-actions
                    span $ {} $ :inner-text "|⌘ / Ctrl + Enter"
                    comp-button "|保存" $ opts ButtonOptions :kind :primary :on-click $ dispatch-fn (_e d!)
                      d! $ :: :submit
                div
                  {} $ :class-name |section-title
                  h2 $ {} $ :inner-text "|最近内容"
                  comp-button "|刷新" $ opts ButtonOptions :class-name |btn-sm :on-click $ dispatch-fn (_e d!)
                    d! $ :: :refresh
                if (empty? snippets)
                  p $ {} (:class-name |empty) (:inner-text "|还没有内容，先保存第一条吧。")
                  list->
                    {} $ :class-name |snippets
                    for-keyed snippets
                      fn (snippet)
                        hint-fn $ Fn app.schema/Snippet $ -> String
                        str $ :id snippet
                      fn (snippet _idx)
                        hint-fn $ Fn app.schema/Snippet Number $ -> Dynamic
                        comp-snippet snippet $ includes? expanded $ :id snippet
          :examples $ []
          :schema $ quote $ Fn app.schema/Store (-> respo.schema/Component)
        'comp-container $ %{} 'CodeEntry
          :doc "|Root view: header with sync status, then the login panel or the board."
          :code $ quote $ defcomp comp-container (store)
            div
              {} $ :class-name $ str-spaced css/global |shell
              create-element :header ({})
                div
                  {} $ :class-name |brand
                  span
                    {} (:class-name |brand-mark) (:aria-hidden |true)
                    span $ {}
                    span $ {}
                  h1 ({}) (<> |Copyboard)
                    span $ {} (:class-name |lite) (:inner-text "| Lite")
                span $ {}
                  :class-name $ str-spaced |status $ :status-kind store
                  :inner-text $ :status store
              if (:logged-in? store) (comp-board store) (comp-login store)
          :examples $ []
          :schema $ quote $ Fn app.schema/Store (-> respo.schema/Component)
        'comp-login $ %{} 'CodeEntry
          :doc "|Login panel. Enter in the password field submits."
          :code $ quote $ defcomp comp-login (store)
            create-element :section
              {} $ :class-name |login-panel
              span $ {} (:class-name |section-kicker) (:inner-text "|PRIVATE CLIPBOARD")
              h2 ({}) (<> "|随手保存，")
                create-element :br $ {}
                <> "|随时取用。"
              p $ {} $ :inner-text "|登录后即可访问你的私人剪贴板。内容只对你可见。"
              div
                {} $ :class-name |login-form
                create-element :label $ {} (:for |username) (:inner-text "|用户名")
                input $ {} (:id |username)
                  :value $ :username store
                  :autocomplete |username
                  :placeholder "|输入用户名"
                  :class-name css/input
                  :on-input $ fn (e d!)
                    d! $ :: :username $ event-value e
                create-element :label $ {} (:for |password) (:inner-text "|密码")
                input $ {} (:id |password) (:type |password)
                  :value $ :password store
                  :autocomplete |current-password
                  :placeholder "|输入密码"
                  :class-name css/input
                  :on-input $ fn (e d!)
                    d! $ :: :password $ event-value e
                  :on-keydown $ fn (e d!)
                    when
                      = |Enter $ :key $ keyboard-info e
                      d! $ :: :login
                comp-button "|登录" $ opts ButtonOptions :kind :primary :class-name |login-submit :on-click $ dispatch-fn (_e d!)
                  d! $ :: :login
          :examples $ []
          :schema $ quote $ Fn app.schema/Store (-> respo.schema/Component)
        'comp-snippet $ %{} 'CodeEntry
          :doc "|One snippet. Long content is clamped to a fixed height; expanding keeps a taller limit and scrolls inside."
          :code $ quote $ defcomp comp-snippet (snippet expanded?)
            let
                id $ :id snippet
                content $ :content snippet
                long? $ long-content? content
                link $ link-href content
              create-element :article
                {} $ :class-name |snippet
                div
                  {}
                    :class-name $ str-spaced |snippet-body $ if long? (if expanded? |is-expanded |is-collapsed) |
                    :title $ if
                      and long? $ not expanded?
                      , "|点击展开" |
                    :on-click $ fn (_e d!)
                      when
                        and long? $ not expanded?
                        d! $ :: :toggle-expand id
                  p ({})
                    if (.some? link)
                      a $ {}
                        :href $ .unwrap link
                        :target |_blank
                        :rel "|noopener noreferrer"
                        :inner-text content
                      <> content
                div
                  {} $ :class-name |snippet-actions
                  create-element :time $ {} $ :inner-text
                    shared/date-local-string $ shared/date-from-ms $ :created-at snippet
                  if long?
                    comp-button (if expanded? "|收起" "|展开")
                      opts ButtonOptions :class-name |btn-sm :on-click $ dispatch-fn (_e d!)
                        d! $ :: :toggle-expand id
                    span $ {}
                  comp-button "|复制" $ opts ButtonOptions :class-name |btn-sm :on-click $ dispatch-fn (_e d!)
                    d! $ :: :copy content
                  comp-button "|删除" $ opts ButtonOptions :kind :danger-outline :class-name |btn-sm :on-click $ dispatch-fn (_e d!)
                    d! $ :: :remove id
          :examples $ []
          :schema $ quote $ Fn app.schema/Snippet Bool (-> respo.schema/Component) (:features :js-ffi)
        'link-href $ %{} 'CodeEntry
          :doc "|Return the normalized URL when the whole content is a single http(s) link."
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
        'long-content? $ %{} 'CodeEntry
          :doc "|Content longer than about six rendered lines gets collapsed."
          :code $ quote $ defn long-content? (content)
            or
              > (.len content) 360
              >
                .len $ .split-lines content
                , 6
          :examples $ []
          :schema $ quote $ Fn String (-> Bool)
      :ns $ %{} 'NsEntry (:doc |)
        :code $ quote $ ns app.comp
          :require
            respo.core :refer $ defcomp div span strong p a h1 h2 input textarea list-> create-element <> event-value keyboard-info for-keyed dispatch-fn
            respo-ui.comp :refer $ comp-button
            respo-ui.schema :refer $ ButtonOptions opts
            respo-ui.css :as css
            js-ffi.shared :as shared
    'app.lite $ %{} 'FileEntry
      :defs $ {}
        '*store $ %{} 'CodeEntry
          :doc "|Global UI state; every change re-renders through the :render watch."
          :code $ quote $ defref *store schema/store
          :examples $ []
          :schema $ quote $ Ref app.schema/Store
        'SnippetArrayHost $ %{} 'CodeEntry (:doc |)
          :code $ quote $ deftrait SnippetArrayHost (:length 'Number)
            .for-each! $ quote $ Fn app.lite/SnippetArrayHost
              Fn JsObject Number JsObject $ -> Unit
              -> Unit
          :examples $ []
          :ffi $ {} (:backend :js) (:kind :external-object) (:target :browser)
            :names $ {} $ :for-each! |forEach
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
        'copy-content! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn copy-content! (content) (browser/clipboard-write-text! content) (set-status! "|已复制" |online)
          :examples $ []
          :schema $ quote $ Fn String (-> Unit)
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
                                  snippet $ decode-snippet created
                                swap! *store $ fn (store)
                                  hint-fn $ Fn app.schema/Store $ -> app.schema/Store
                                  -> store
                                    .assoc :snippets $ prepend (:snippets store) snippet
                                    .assoc :draft |
                                focus-composer!
                                set-status! "|已保存" |online
                            (:err error) (raise error)
                        handle-response-failure! (response :status) "|保存失败"
                  (:err error) (raise error)
              fn (error) (shared/console-error! |Failed-to-create-snippet) (set-status! "|保存失败" |error)
          :examples $ []
          :schema $ quote $ Fn String (-> Unit) (:features :js-ffi) (:async)
        'decode-snippet $ %{} 'CodeEntry
          :doc "|Validate one snippet object from the backend JSON."
          :code $ quote $ defn decode-snippet (raw-snippet)
            let
                snippet $ contract/expect-object |snippet raw-snippet
                id $ contract/expect-number |id $ contract/object-field |snippet snippet |id
                content $ contract/expect-string |content $ contract/object-field |snippet snippet |content
                created-at $ contract/expect-number |created_at $ contract/object-field |snippet snippet |created_at
              Snippet :id id :content content :created-at created-at
          :examples $ []
          :schema $ quote $ Fn JsObject (-> app.schema/Snippet) (:features :js-ffi)
        'decode-snippets $ %{} 'CodeEntry
          :doc "|Validate the backend snippet array into an immutable list, keeping order."
          :code $ quote $ defn decode-snippets (value)
            let
                *result $ ref $ assert-type ([])
                  quote $ List app.schema/Snippet
              .for-each! (checked-snippet-array value)
                fn (raw-snippet _index _array)
                  swap! *result $ fn (xs)
                    hint-fn $ Fn (List app.schema/Snippet)
                      -> $ List app.schema/Snippet
                    append xs $ decode-snippet raw-snippet
                  , &unit
              , @*result
          :examples $ []
          :schema $ quote $ Fn JsObject
            -> $ List app.schema/Snippet
            :features :js-ffi
        'dispatch! $ %{} 'CodeEntry
          :doc "|Run effect ops, and pass the rest to the pure updater."
          :code $ quote $ defn dispatch! (op)
            match op
              (:submit) (submit-content!)
              (:login) (login!)
              (:logout) (logout!)
              (:refresh)
                do (set-status! "|刷新中" |online) (load-snippets!)
              (:remove id) (remove-snippet! id)
              (:copy content) (copy-content! content)
              _ $ reset! *store $ updater @*store op
            , &unit
          :examples $ []
          :schema $ quote $ Fn app.schema/Op (-> Unit)
        'focus-composer! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn focus-composer! ()
            match (browser/query-selector |#content)
              (:some input) (browser/element-focus! input)
              (:none) &unit
          :examples $ []
          :schema $ quote $ Fn (-> Unit)
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
                                  items $ decode-snippets snippets
                                swap! *store $ fn (store)
                                  hint-fn $ Fn app.schema/Store $ -> app.schema/Store
                                  -> store (.assoc :snippets items) (.assoc :logged-in? true) (.assoc :user username)
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
                  username $ :username @*store
                  password $ :password @*store
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
                                  swap! *store $ fn (store)
                                    hint-fn $ Fn app.schema/Store $ -> app.schema/Store
                                    .assoc store :password |
                                  set-status! "|正在同步" |online
                                  js-await $ load-snippets!
                                  focus-composer!
                              (:err error) (raise error)
                          do (logout!) (set-status! "|登录失败" |error)
                    (:err error) (raise error)
              fn (error) (shared/console-error! |Failed-to-login) (set-status! "|登录失败" |error)
          :examples $ []
          :schema $ quote $ Fn (-> Unit) (:features :js-ffi) (:async)
        'logout! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn logout! () (browser/storage-remove! |copyboard-lite-token) (browser/storage-remove! |copyboard-lite-user)
            swap! *store $ fn (store)
              hint-fn $ Fn app.schema/Store $ -> app.schema/Store
              -> store (.assoc :logged-in? false) (.assoc :user |)
                .assoc :snippets $ []
                .assoc :expanded $ #{}
                .assoc :status "|请登录"
                .assoc :status-kind |
            , &unit
          :examples $ []
          :schema $ quote $ Fn (-> Unit)
        'main! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn main! () (watch-store!) (render-app!) (wire-events!)
            if
              .some? $ get-token
              do (set-status! "|验证登录" |online) (load-snippets!)
              set-status! "|请登录" |
            println |Copyboard-Lite-started
          :examples $ []
          :schema $ quote $ Fn (-> Unit)
        'mount-target $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn mount-target ()
            .unwrap $ query-selector |#app
          :examples $ []
          :schema $ quote $ Fn (-> respo.dom/DomElement) (:features :js-ffi)
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
          :code $ quote $ defn reload! () (remove-watch! *store :render) (clear-cache!) (watch-store!) (render-app!) (println |Copyboard-Lite-reloaded)
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
        'render-app! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn render-app! ()
            render! (mount-target) (comp-container @*store) dispatch!
          :examples $ []
          :schema $ quote $ Fn (-> Unit) (:features :js-ffi)
        'set-status! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn set-status! (label kind)
            swap! *store $ fn (store)
              hint-fn $ Fn app.schema/Store $ -> app.schema/Store
              -> store (.assoc :status label) (.assoc :status-kind kind)
            , &unit
          :examples $ []
          :schema $ quote $ Fn String String (-> Unit)
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
                content $ :draft @*store
              when
                >
                  .len $ .trim content
                  , 0
                do (set-status! "|保存中" |online) (create-snippet! content)
              , &unit
          :examples $ []
          :schema $ quote $ Fn (-> Unit)
        'watch-store! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn watch-store! ()
            add-watch! *store :render $ fn (_store _prev)
              hint-fn $ Fn app.schema/Store app.schema/Store $ -> Unit
              render-app!
              , &unit
          :examples $ []
          :schema $ quote $ Fn (-> Unit)
        'wire-events! $ %{} 'CodeEntry
          :doc "|Refresh when the page comes back; each successful request renews the session token."
          :code $ quote $ defn wire-events! ()
            browser/document-add-event-listener! |visibilitychange $ fn (_event) (refresh-if-active!)
            browser/add-event-listener! |focus $ fn (_event) (refresh-if-active!)
            browser/add-event-listener! |online $ fn (_event) (refresh-if-active!)
          :examples $ []
          :schema $ quote $ Fn (-> Unit) (:features :js-ffi)
      :ns $ %{} 'NsEntry (:doc |)
        :code $ quote $ ns app.lite
          :require (js-ffi.browser :as browser) (js-ffi.shared :as shared) (js-ffi.contract :as contract) (app.schema :as schema)
            app.schema :refer $ Snippet
            app.updater :refer $ updater
            app.comp :refer $ comp-container
            respo.core :refer $ render! clear-cache!
            respo.ffi.browser :refer $ query-selector
    'app.schema $ %{} 'FileEntry
      :defs $ {}
        'Op $ %{} 'CodeEntry
          :doc "|Application operations dispatched from Respo events. Effect ops are handled by app.lite/dispatch! before the pure updater."
          :code $ quote $ defenum Op (:draft 'String) (:username 'String) (:password 'String) (:toggle-expand 'Number) (:submit) (:login) (:logout) (:refresh) (:remove 'Number) (:copy 'String)
          :examples $ []
          :schema $ quote EnumDef
        'Snippet $ %{} 'CodeEntry
          :doc "|One clipboard item decoded from the backend JSON."
          :code $ quote $ defstruct Snippet (:id 'Number) (:content 'String) (:created-at 'Number)
          :examples $ []
          :schema $ quote StructDef
        'Store $ %{} 'CodeEntry
          :doc "|Whole UI state rendered by app.comp/comp-container."
          :code $ quote $ defstruct Store (:logged-in? 'Bool) (:user 'String) (:status 'String) (:status-kind 'String) (:draft 'String) (:username 'String) (:password 'String)
            :snippets $ quote $ List app.schema/Snippet
            :expanded $ quote $ Set Number
          :examples $ []
          :schema $ quote StructDef
        'store $ %{} 'CodeEntry
          :doc "|Initial store before the saved token is checked."
          :code $ quote $ def store
            Store :logged-in? false :user | :status "|连接中" :status-kind | :draft | :username | :password | :snippets ([]) :expanded $ #{}
          :examples $ []
          :schema $ quote app.schema/Store
      :ns $ %{} 'NsEntry (:doc |)
        :code $ quote $ ns app.schema
    'app.updater $ %{} 'FileEntry
      :defs $ {} $ 'updater
        %{} 'CodeEntry
          :doc "|Pure store transitions for input drafts and expanded snippets. Effect ops leave the store unchanged here."
          :code $ quote $ defn updater (store op)
            match op
              (:draft text) (.assoc store :draft text)
              (:username text) (.assoc store :username text)
              (:password text) (.assoc store :password text)
              (:toggle-expand id)
                let
                    expanded $ :expanded store
                  .assoc store :expanded $ if (includes? expanded id) (exclude expanded id) (include expanded id)
              _ store
          :examples $ []
          :schema $ quote $ Fn app.schema/Store app.schema/Op (-> app.schema/Store)
      :ns $ %{} 'NsEntry (:doc |)
        :code $ quote $ ns app.updater
