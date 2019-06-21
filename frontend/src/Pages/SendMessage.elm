module Pages.SendMessage exposing (Model, view, Msg(..), update)
import Element.Background
import Json.Encode as E

import Element
import Element.Font
import Element.Input
import Http
import RemoteData exposing (RemoteData(..))
import Routes exposing (Route(..), getViewTopicPath)
import Shared exposing (Flags, getLinkStyle, viewHttpError)
import Topic exposing (TopicDetail)


type alias Model =
    { topicDetailResponse : RemoteData Http.Error TopicDetail
    , partition : Int
    , message : Maybe String
    }


type Msg
    = ChangeSendMessage String
    | ChangeSendMessagePartition Int
    | SendMessage String Int String
    | SendMessageResponse (Result Http.Error ())


update : Flags -> Msg -> Model -> ( Model, Cmd Msg )
update flags msg model =
    case msg of

        SendMessage topicName partition message ->
            ( model, sendMessage flags.apiUrl topicName partition message )

        SendMessageResponse _ ->
            ( model, Cmd.none )

        ChangeSendMessage message ->
            let
                newModel =
                    { model | message = Just message }
            in
            ( newModel, Cmd.none )

        ChangeSendMessagePartition partition ->
            let
                newModel =
                    { model | partition = partition }
            in
            ( newModel, Cmd.none )



encodeSendMessageRequest : Int -> String -> E.Value
encodeSendMessageRequest partition message =
    E.object
        [ ( "message", E.string message )
        , ( "partition", E.int partition )
        ]


sendMessage : String -> String -> Int -> String -> Cmd Msg
sendMessage apiUrl topicName partition message =
    let
        body =
            Http.jsonBody (encodeSendMessageRequest partition message)

        url =
            apiUrl ++ "/api/topic/" ++ topicName ++ "/sendMessage"
    in
    Http.request
        { method = "POST"
        , url = url
        , body = body
        , tracker = Nothing
        , timeout = Nothing
        , headers = []
        , expect = Http.expectWhatever SendMessageResponse
        }



view : Model -> Element.Element Msg
view model =
    let
        topicName =
            case model.topicDetailResponse of
                Success topic ->
                    topic.name

                _ ->
                    "Loading..."

        body =
            case model.topicDetailResponse of
                NotAsked ->
                    Element.el [] (Element.text "This should not have happened...")

                Success topic ->
                    viewMessageForm model.partition model.message topic

                Failure error ->
                    viewHttpError error

                Loading ->
                    Element.el [] (Element.text "Loading...")
    in
    Element.column [ Element.width Element.fill ]
        [ Element.row
            [ Element.paddingEach
                { top = 100
                , bottom = 16
                , left = 0
                , right = 0
                }
            , Element.centerX
            , Element.centerY
            ]
            [ Element.el [ Element.Font.size 62 ] (Element.text topicName) ]
        , Element.row [ Element.width Element.fill ] [ body ]
        ]


viewMessageForm : Int -> Maybe String -> TopicDetail -> Element.Element Msg
viewMessageForm partition maybeMessage topicDetail =
    Element.column [ Element.spacingXY 0 16, Element.width Element.fill ]
        [ Element.link getLinkStyle { url = getViewTopicPath topicDetail.name, label = Element.text "Back to detail view" }
        , Element.row [] [ Element.text ("Partition: " ++ String.fromInt partition) ]
        , Element.row [] [ Element.text "Message: " ]
        , Element.row [ Element.width Element.fill ]
            [ Element.Input.multiline
                [ Element.height (Element.px 680)
                ]
                { onChange = ChangeSendMessage
                , text = Maybe.withDefault "" maybeMessage
                , placeholder = Just (Element.Input.placeholder [] (Element.text "Type you message here"))
                , label = Element.Input.labelHidden "message"
                , spellcheck = False
                }
            ]
        , Element.row
            []
            [ Element.Input.button
                [ Element.Background.color (Element.rgb 0.05 0.5 0.8)
                , Element.paddingXY 16 12
                , Element.Font.color (Element.rgb 1 1 1)
                ]
                { onPress = Just (SendMessage topicDetail.name partition (Maybe.withDefault "" maybeMessage)), label = Element.text "Send" }
            ]
        ]
