port module Main exposing (Model, Msg(..), Page(..), init, main, update, view)

import Browser
import Browser.Navigation exposing (Key)
import Dict exposing (Dict)
import Element
import Element.Background
import Element.Border
import Element.Events
import Element.Font
import Element.Input
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events
import Http
import Json.Decode as D
import Json.Decode.Extra as DExtra
import Json.Encode as E
import RemoteData exposing (RemoteData(..))
import Url exposing (Url)
import Url.Parser as Parser exposing ((</>), (<?>), Parser, oneOf, s)
import Url.Parser.Query as Q



-- MAIN


main : Program Flags Model Msg
main =
    Browser.application
        { view = view
        , init = init
        , onUrlChange = OnUrlChange
        , onUrlRequest = OnUrlRequest
        , update = update
        , subscriptions = always Sub.none
        }


port copy : String -> Cmd msg



-- MODEL


type alias Topic =
    { name : String
    , partitionCount : Int
    }


type alias PartitionOffsets =
    Dict Int Int


type alias TopicDetail =
    { name : String
    , partitionOffsets : PartitionOffsets
    , partitionDetails : List PartitionDetail
    }


type alias PartitionDetail =
    { id : Int
    , highwatermarkOffset : Int
    , messageCount : Int
    , messages : List TopicMessage
    }


type alias TopicMessage =
    { partition : Int
    , offset : Int
    , json : String
    }


type alias Model =
    { apiUrl : String
    , page : Page
    , key : Key
    }


type alias Flags =
    { apiUrl : String }


type alias SendMessagePageModel =
    { topicDetailResponse : RemoteData Http.Error TopicDetail
    , partition : Int
    , message : Maybe String
    }


type alias TopicOverviewPageModel =
    { topicsResponse : RemoteData Http.Error (List Topic)
    }


type alias TopicDetailPageModel =
    { topicDetailResponse : RemoteData Http.Error TopicDetail }


type Page
    = TopicOverview TopicOverviewPageModel
    | TopicDetailPage TopicDetailPageModel
    | SendMessagePage SendMessagePageModel
    | PageNone


type Route
    = RootRoute
    | TopicsRoute
    | SendMessageRoute String Int
    | ViewTopicRoute String PartitionOffsets
    | NotFound


parseUrl : Url -> Route
parseUrl url =
    case Parser.parse routeParser url of
        Just route ->
            route

        Nothing ->
            NotFound


fetchTopics : String -> Cmd Msg
fetchTopics apiUrl =
    Http.get
        { url = apiUrl ++ "/api/topics"
        , expect = Http.expectJson (RemoteData.fromResult >> TopicsResponse) decodeTopics
        }


encodePartitionOffsets : PartitionOffsets -> E.Value
encodePartitionOffsets partitionOffsets =
    E.dict String.fromInt E.int partitionOffsets



-- TODO: Can this be done nicer?


getTopicDetailPath : String -> String -> PartitionOffsets -> String
getTopicDetailPath apiUrl topicName partitionOffsets =
    let
        baseUrl =
            apiUrl ++ "/api/topic/" ++ topicName
    in
    if Dict.size partitionOffsets == 0 then
        baseUrl

    else
        baseUrl
            ++ "/from?offsets="
            ++ Dict.foldl
                (\partition offset acc ->
                    acc ++ String.fromInt partition ++ ";" ++ String.fromInt offset ++ ","
                )
                ""
                partitionOffsets
            |> String.dropRight 1


fetchTopicDetail : String -> String -> PartitionOffsets -> Cmd Msg
fetchTopicDetail apiUrl topicName partitionOffsets =
    let
        body =
            Http.jsonBody (encodePartitionOffsets partitionOffsets)
    in
    Http.request
        { method = "GET"
        , url = getTopicDetailPath apiUrl topicName partitionOffsets
        , body = body
        , tracker = Nothing
        , timeout = Nothing
        , headers = []
        , expect = Http.expectJson (RemoteData.fromResult >> TopicDetailResponse) decodeTopicDetail
        }


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


decodeTopic : D.Decoder Topic
decodeTopic =
    D.map2 Topic
        (D.field "name" D.string)
        (D.field "partition_count" D.int)


decodeTopics : D.Decoder (List Topic)
decodeTopics =
    D.list decodeTopic


decodeTopicDetail : D.Decoder TopicDetail
decodeTopicDetail =
    D.map3 TopicDetail
        (D.field "name" D.string)
        (D.field "partition_offsets" (DExtra.dict2 D.int D.int))
        decodeAndSortPartitionDetailList


decodeTopicMessage : D.Decoder TopicMessage
decodeTopicMessage =
    D.map3 TopicMessage
        (D.field "partition" D.int)
        (D.field "offset" D.int)
        (D.field "json" D.string)


decodeAndSortPartitionDetailList : D.Decoder (List PartitionDetail)
decodeAndSortPartitionDetailList =
    D.map (List.sortBy .id) (D.field "partition_details" (D.list decodePartitionDetail))


decodePartitionDetail : D.Decoder PartitionDetail
decodePartitionDetail =
    D.map4 PartitionDetail
        (D.field "id" D.int)
        (D.field "highwatermark_offset" D.int)
        (D.field "message_count" D.int)
        (D.field "messages" (D.list decodeTopicMessage))


routeParser : Parser (Route -> a) a
routeParser =
    oneOf
        [ Parser.map RootRoute Parser.top
        , Parser.map ViewTopicRoute (s "topic" </> Parser.string <?> partitionOffsetUrlParser)
        , Parser.map SendMessageRoute (s "topic" </> Parser.string </> s "sendMessage" </> Parser.int)
        , Parser.map TopicsRoute (s "topics")
        ]


partitionOffsetUrlParser : Q.Parser PartitionOffsets
partitionOffsetUrlParser =
    Q.custom "offsets" listToPartitionOffset


listToPartitionOffset : List String -> PartitionOffsets
listToPartitionOffset list =
    List.foldl foldOffset
        Dict.empty
        list



-- TODO: Can this be done nicer?


foldOffset : String -> PartitionOffsets -> PartitionOffsets
foldOffset str dict =
    case String.split ";" str of
        [ partition, offsets ] ->
            case ( String.toInt partition, String.toInt offsets ) of
                ( Just p, Just o ) ->
                    Dict.insert p o dict

                _ ->
                    dict

        _ ->
            dict


getPath : Route -> String
getPath route =
    case route of
        NotFound ->
            "/404"

        TopicsRoute ->
            "/topics"

        SendMessageRoute topicName partition ->
            "/topic/" ++ topicName ++ "/sendMessage/" ++ String.fromInt partition

        RootRoute ->
            "/topics"

        ViewTopicRoute name partitionOffsets ->
            "/topic/" ++ name ++ getTopicOffsetUrl partitionOffsets


getPage : String -> Maybe String -> Route -> ( Page, Cmd Msg )
getPage apiUrl maybeMessage route =
    case route of
        NotFound ->
            ( PageNone, Cmd.none )

        SendMessageRoute topicName partition ->
            let
                model =
                    { topicDetailResponse = Loading, partition = partition, message = maybeMessage }
            in
            ( SendMessagePage model, fetchTopicDetail apiUrl topicName Dict.empty )

        RootRoute ->
            ( TopicOverview { topicsResponse = Loading }, fetchTopics apiUrl )

        TopicsRoute ->
            ( TopicOverview { topicsResponse = Loading }, fetchTopics apiUrl )

        ViewTopicRoute name partitionOffsets ->
            ( TopicDetailPage { topicDetailResponse = Loading }, fetchTopicDetail apiUrl name partitionOffsets )


init : Flags -> Url -> Key -> ( Model, Cmd Msg )
init flags url key =
    let
        ( page, cmd ) =
            parseUrl url |> getPage flags.apiUrl Nothing
    in
    ( { apiUrl = flags.apiUrl, page = page, key = key }, cmd )


type Msg
    = OnUrlRequest Browser.UrlRequest
    | OnUrlChange Url
    | ChangeSendMessage String
    | ChangeSendMessagePartition Int
    | SendMessage String Int String
    | SendMessageResponse (Result Http.Error ())
    | TopicsResponse (RemoteData Http.Error (List Topic))
    | TopicDetailResponse (RemoteData Http.Error TopicDetail)
    | Copy String
    | Noop


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Noop ->
            ( model, Cmd.none )

        Copy message ->
            ( model, copy message )

        OnUrlChange url ->
            let
                ( newPage, cmd ) =
                    parseUrl url |> getPage model.apiUrl Nothing
            in
            ( { model | page = newPage }, cmd )

        OnUrlRequest urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model
                    , Browser.Navigation.pushUrl model.key (Url.toString url)
                    )

                Browser.External url ->
                    ( model
                    , Browser.Navigation.load url
                    )

        SendMessage topicName partition message ->
            ( model, sendMessage model.apiUrl topicName partition message )

        SendMessageResponse _ ->
            ( model, Cmd.none )

        ChangeSendMessage message ->
            let
                newModel =
                    case model.page of
                        SendMessagePage sendMessageModel ->
                            let
                                newPageModel =
                                    { sendMessageModel | message = Just message }
                            in
                            { model | page = SendMessagePage newPageModel }

                        _ ->
                            model
            in
            ( newModel, Cmd.none )

        ChangeSendMessagePartition partition ->
            let
                newModel =
                    case model.page of
                        SendMessagePage sendMessageModel ->
                            let
                                newPageModel =
                                    { sendMessageModel | partition = partition }
                            in
                            { model | page = SendMessagePage newPageModel }

                        _ ->
                            model
            in
            ( newModel, Cmd.none )

        TopicsResponse response ->
            let
                newPage =
                    case model.page of
                        TopicOverview _ ->
                            TopicOverview { topicsResponse = response }

                        _ ->
                            model.page
            in
            ( { model | page = newPage }
            , Cmd.none
            )

        TopicDetailResponse response ->
            let
                newPage =
                    case model.page of
                        TopicDetailPage _ ->
                            TopicDetailPage { topicDetailResponse = response }

                        SendMessagePage sendMessagePageModel ->
                            SendMessagePage { sendMessagePageModel | topicDetailResponse = response }

                        _ ->
                            model.page
            in
            ( { model | page = newPage }
            , Cmd.none
            )



---- VIEW ----


view : Model -> Browser.Document Msg
view model =
    { title = "Kafka UI"
    , body =
        [ Element.layout [] <|
            Element.column
                [ Element.width Element.fill
                , Element.Font.family
                    [ Element.Font.monospace
                    ]
                ]
                [ header, viewBody model ]
        ]
    }


header : Element.Element Msg
header =
    Element.row
        [ Element.centerX, Element.width Element.fill, Element.height (Element.px 64), Element.Background.color (Element.rgb 0.3 0.3 0.3) ]
        [ Element.row [ Element.width (Element.fill |> Element.maximum 1600), Element.centerX ]
            [ Element.link
                ([ Element.centerY ] ++ getLinkStyle)
                { url = getPath TopicsRoute
                , label = Element.text "Topics"
                }
            ]
        ]


viewBody : Model -> Element.Element Msg
viewBody model =
    let
        body =
            case model.page of
                TopicDetailPage pageModel ->
                    viewTopicDetailPage pageModel

                TopicOverview pageModel ->
                    viewTopicOverview pageModel

                SendMessagePage sendMessagePageModel ->
                    viewSendMessage sendMessagePageModel

                -- [ viewSendMessage sendMessagePageModel ]
                PageNone ->
                    Element.el [] (Element.text "Sorry, can't find this page")
    in
    Element.column [ Element.width (Element.fill |> Element.maximum 1600), Element.centerX ]
        [ body ]


viewSendMessage : SendMessagePageModel -> Element.Element Msg
viewSendMessage model =
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
        [ Element.link getLinkStyle { url = getPath (ViewTopicRoute topicDetail.name Dict.empty), label = Element.text "Back to detail view" }
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


viewTopicDetailPage : TopicDetailPageModel -> Element.Element Msg
viewTopicDetailPage model =
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
                    viewTopicDetail topic

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


viewTopicDetail : TopicDetail -> Element.Element Msg
viewTopicDetail topicDetail =
    let
        olderLink =
            getPath (ViewTopicRoute topicDetail.name topicDetail.partitionOffsets)

        newerLink =
            getPath (ViewTopicRoute topicDetail.name (addToOffsets 20 topicDetail.partitionOffsets))

        sendMessageLink =
            \partition -> getPath (SendMessageRoute topicDetail.name partition)
    in
    Element.column
        [ Element.width Element.fill, Element.spacingXY 0 32 ]
        (List.map (viewPartitionDetail olderLink newerLink sendMessageLink) topicDetail.partitionDetails)


viewTopicDetailTableHeader : String -> String -> (Int -> String) -> PartitionDetail -> Element.Element Msg
viewTopicDetailTableHeader olderLink newerLink sendMessageLink partitionDetail =
    Element.row [ Element.width Element.fill ]
        [ Element.column [ Element.spacingXY 0 16 ]
            [ Element.row []
                [ Element.el [] (Element.text ("Partititon [" ++ String.fromInt partitionDetail.id ++ "]"))
                ]
            , Element.row []
                [ Element.el [] (Element.text ("High watermark offset [" ++ String.fromInt partitionDetail.highwatermarkOffset ++ "]"))
                ]
            , Element.row []
                [ Element.link getLinkStyle { label = Element.text "Send message on to this topic and partition", url = sendMessageLink partitionDetail.id }
                ]
            ]
        , Element.column [ Element.width Element.fill ]
            [ Element.row [ Element.alignRight ]
                [ Element.link getLinkStyle { label = Element.text "newer", url = newerLink }
                , Element.el [] (Element.text "/")
                , Element.link getLinkStyle { label = Element.text "older", url = olderLink }
                ]
            ]
        ]


viewTopicDetailTableBody : PartitionDetail -> Element.Element Msg
viewTopicDetailTableBody partitionDetail =
    Element.row []
        [ Element.indexedTable [ Element.Font.alignLeft ]
            { data = partitionDetail.messages
            , columns =
                [ { header = Element.el [ Element.paddingXY 24 12 ] (Element.text "Offset")
                  , width = Element.px 150
                  , view = viewTableOffset
                  }
                , { header = Element.el [ Element.paddingXY 24 12 ] (Element.text "Message")
                  , width = Element.fill
                  , view = viewTableMessage
                  }
                , { header = Element.el [ Element.paddingXY 24 12 ] (Element.text "Actions")
                  , width = Element.px 120
                  , view = viewTableActions
                  }
                ]
            }
        ]


getTableBackground : Int -> Element.Color
getTableBackground index =
    if modBy 2 index == 0 then
        Element.rgb 0.94 0.94 0.94

    else
        Element.rgb 1 1 1


viewTableMessage : Int -> TopicMessage -> Element.Element Msg
viewTableMessage index message =
    Element.paragraph
        [ Element.paddingXY 24 12
        , Element.Background.color (getTableBackground index)
        , Element.height Element.fill
        ]
        [ Element.text message.json ]


viewTableActions : Int -> TopicMessage -> Element.Element Msg
viewTableActions index message =
    Element.paragraph
        [ Element.paddingXY 24 12
        , Element.Background.color (getTableBackground index)
        , Element.height Element.fill
        , Element.Events.onClick (Copy message.json)
        ]
        [ Element.el ([ Element.pointer ] ++ getLinkStyle) (Element.text "Copy") ]


viewTableOffset : Int -> TopicMessage -> Element.Element Msg
viewTableOffset index message =
    Element.el
        [ Element.paddingXY 24 12
        , Element.Background.color (getTableBackground index)
        , Element.height Element.fill
        ]
        (Element.text (String.fromInt message.offset))


viewPartitionDetail : String -> String -> (Int -> String) -> PartitionDetail -> Element.Element Msg
viewPartitionDetail olderLink newerLink sendMessageLink partitionDetail =
    Element.column [ Element.spacingXY 0 24, Element.width Element.fill ]
        [ viewTopicDetailTableHeader olderLink newerLink sendMessageLink partitionDetail
        , viewTopicDetailTableBody partitionDetail
        ]


viewTopicOverview : TopicOverviewPageModel -> Element.Element Msg
viewTopicOverview model =
    let
        body =
            case model.topicsResponse of
                NotAsked ->
                    Element.el [] (Element.text "This should not have happened...")

                Success topics ->
                    viewTopicList topics

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
            [ Element.el [ Element.Font.size 62 ] (Element.text "All topics") ]
        , Element.row [ Element.width Element.fill ] [ body ]
        ]


viewHttpError : Http.Error -> Element.Element Msg
viewHttpError error =
    let
        message =
            case error of
                Http.BadUrl str ->
                    [ Element.paragraph [] [ Element.el [] (Element.text "Something is wrong with the url:") ]
                    , Element.paragraph [] [ Element.el [] (Element.text str) ]
                    ]

                Http.Timeout ->
                    [ Element.paragraph [] [ Element.el [] (Element.text "Request timed out!") ] ]

                Http.NetworkError ->
                    [ Element.paragraph [] [ Element.el [] (Element.text "Network error!") ] ]

                Http.BadStatus status ->
                    [ Element.paragraph [] [ Element.el [] (Element.text ("Got status code [" ++ String.fromInt status ++ "]")) ] ]

                Http.BadBody body ->
                    [ Element.paragraph [] [ Element.el [] (Element.text "Got unexpected body:") ]
                    , Element.paragraph [] [ Element.el [] (Element.text body) ]
                    ]
    in
    Element.column [ Element.width Element.fill, Element.Background.color (Element.rgb 0.7 0.4 0.4), Element.padding 24 ]
        [ Element.el
            []
            (Element.textColumn [ Element.width Element.fill ] message)
        ]


getLinkStyle =
    [ Element.Font.bold, Element.Font.color (Element.rgb 0.06 0.5 0.8) ]


viewTopicList : List Topic -> Element.Element Msg
viewTopicList topics =
    let
        viewRow : Topic -> Element.Element Msg
        viewRow =
            \topic ->
                Element.row
                    [ Element.width Element.fill
                    , Element.Border.color (Element.rgb 0.95 0.95 0.95)
                    , Element.Border.solid
                    , Element.Border.widthEach
                        { top = 1
                        , bottom = 0
                        , right = 0
                        , left = 0
                        }
                    , Element.paddingEach
                        { top = 12
                        , bottom = 24
                        , right = 0
                        , left = 0
                        }
                    ]
                    [ Element.link
                        ([] ++ getLinkStyle)
                        { url = getPath (ViewTopicRoute topic.name Dict.empty)
                        , label = Element.text topic.name
                        }
                    ]
    in
    Element.column [ Element.width Element.fill ] (List.map viewRow topics)


getTopicOffsetUrl : PartitionOffsets -> String
getTopicOffsetUrl offsets =
    Dict.foldl
        (\a b str -> str ++ "offsets=" ++ String.fromInt a ++ ";" ++ String.fromInt b ++ "&")
        "?"
        offsets


addToOffsets : Int -> PartitionOffsets -> PartitionOffsets
addToOffsets n offsets =
    Dict.map (\_ offset -> offset + n) offsets
