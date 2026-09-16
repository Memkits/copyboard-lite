
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
        'api-base $ %{} 'CodeEntry (:doc |)
          :code $ quote $ def api-base |http://127.0.0.1:11030
          :examples $ []
          :schema $ :: 'Dynamic
        'create-snippet! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn create-snippet! (content)
            hint-fn $ {} $ :async true
            try
              let
                  response $ js-await $ js/fetch (str api-base |/api/snippets)
                    js-object (:method |POST)
                      :headers $ js-object $ |Content-Type |application/json
                      :body $ js/JSON.stringify $ js-object (:content content)
                if (.-ok response)
                  do
                    set!
                      .-value $ unsafe-coerce (js/document.querySelector |#content) JsObject
                      , |
                    js-await $ load-snippets!
                  raise |Failed-to-create-snippet
              fn (error)
                do (js/console.error |Failed-to-create-snippet error) (set-status! "|保存失败" |error)
          :examples $ []
          :schema $ :: 'Dynamic
        'load-snippets! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn load-snippets! ()
            hint-fn $ {} $ :async true
            try
              let
                  response $ js-await $ js/fetch (str api-base |/api/snippets)
                  snippets $ js-await $ .!json response
                if (.-ok response)
                  do (render-snippets! snippets) (set-status! "|已连接" |online)
                  raise |Failed-to-load-snippets
              fn (error)
                do (js/console.error |Failed-to-load-snippets error) (set-status! "|连接失败" |error)
          :examples $ []
          :schema $ :: 'Dynamic
        'main! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn main! () (wire-events!) (load-snippets!) (println |Copyboard-Lite-started)
          :examples $ []
          :schema $ :: 'Dynamic
        'reload! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn reload! () (load-snippets!) (println |Copyboard-Lite-reloaded)
          :examples $ []
          :schema $ :: 'Dynamic
        'remove-snippet! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn remove-snippet! (id)
            hint-fn $ {} $ :async true
            try
              let
                  response $ js-await $ js/fetch (str api-base |/api/snippets/ id)
                    js-object $ :method |DELETE
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
        'wire-events! $ %{} 'CodeEntry (:doc |)
          :code $ quote $ defn wire-events! ()
            let
                form $ unsafe-coerce (js/document.querySelector |#snippet-form) JsObject
                refresh $ unsafe-coerce (js/document.querySelector |#refresh) JsObject
              .!addEventListener form |submit $ fn (event)
                do (.!preventDefault event)
                  let
                      input $ unsafe-coerce (js/document.querySelector |#content) JsObject
                      content $ unsafe-coerce (.-value input) String
                    when
                      >
                        unsafe-coerce (.-length content) Number
                        , 0
                      create-snippet! content
              .!addEventListener refresh |click $ fn (_event) (load-snippets!)
          :examples $ []
          :schema $ :: 'Dynamic
      :ns $ %{} 'NsEntry (:doc |)
        :code $ quote $ ns app.lite
