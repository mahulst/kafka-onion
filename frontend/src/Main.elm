module Main exposing (Model, Msg(..), Page(..), init, main, update, view)

import Browser
import Browser.Navigation exposing (Key)
import Dict exposing (Dict)
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


type Page
    = TopicOverview (RemoteData Http.Error (List Topic))
    | TopicDetailPage (RemoteData Http.Error TopicDetail)
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
            ( TopicOverview Loading, fetchTopics apiUrl )

        TopicsRoute ->
            ( TopicOverview Loading, fetchTopics apiUrl )

        ViewTopicRoute name partitionOffsets ->
            ( TopicDetailPage Loading, fetchTopicDetail apiUrl name partitionOffsets )


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
    | Noop


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Noop ->
            ( model, Cmd.none )

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
                            TopicOverview response

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
                            TopicDetailPage response

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
        case model.page of
            TopicDetailPage topic ->
                [ viewTopicDetail topic ]

            TopicOverview topics ->
                [ viewTopics topics ]

            SendMessagePage sendMessagePageModel ->
                [ viewSendMessage sendMessagePageModel ]

            PageNone ->
                [ div [] [ text "Can not find page" ] ]
    }


viewSendMessage : SendMessagePageModel -> Html Msg
viewSendMessage model =
    case model.topicDetailResponse of
        NotAsked ->
            div [] [ text "Should not be here!" ]

        Success topicDetail ->
            let
                message =
                    Maybe.withDefault "" model.message
            in
            div []
                [ h1 [] [ text topicDetail.name ]
                , Html.a [ href (getPath (ViewTopicRoute topicDetail.name Dict.empty)) ] [ text "Back to detail view" ]
                , div
                    []
                    [ Html.select
                        [ Html.Events.onInput (\input -> ChangeSendMessagePartition (Maybe.withDefault 0 (String.toInt input)))
                        ]
                        (List.map
                            (\partitionDetail ->
                                Html.option
                                    [ Html.Attributes.value (String.fromInt partitionDetail.id)
                                    , Html.Attributes.selected (model.partition == partitionDetail.id)
                                    ]
                                    [ text (String.fromInt partitionDetail.id) ]
                            )
                            topicDetail.partitionDetails
                        )
                    , Html.textarea [ Html.Attributes.rows 50, Html.Attributes.value message, Html.Events.onInput ChangeSendMessage ] []
                    , Html.button [ Html.Events.onClick (SendMessage topicDetail.name model.partition (Maybe.withDefault "" model.message)) ] [ text "Send" ]
                    ]
                ]

        Failure error ->
            div [] [ text "Something went wrong while fetching topic" ]

        Loading ->
            div [] [ text "Loading topic, please hold on..." ]


getTopicOffsetUrl : PartitionOffsets -> String
getTopicOffsetUrl offsets =
    Dict.foldl
        (\a b str -> str ++ "offsets=" ++ String.fromInt a ++ ";" ++ String.fromInt b ++ "&")
        "?"
        offsets


addToOffsets : Int -> PartitionOffsets -> PartitionOffsets
addToOffsets n offsets =
    Dict.map (\_ offset -> offset + n) offsets


viewTopicDetail : RemoteData Http.Error TopicDetail -> Html Msg
viewTopicDetail topicDetailResponse =
    case topicDetailResponse of
        NotAsked ->
            div [] [ text "Should not be here!" ]

        Success topicDetail ->
            div []
                ([ h1 [] [ text topicDetail.name ]
                 , Html.a [ href (getPath (SendMessageRoute topicDetail.name 0)) ] [ text "Send new message" ]
                 , Html.a [ href (getPath (ViewTopicRoute topicDetail.name topicDetail.partitionOffsets)) ] [ text "Older" ]
                 , Html.a [ href (getPath (ViewTopicRoute topicDetail.name (addToOffsets 20 topicDetail.partitionOffsets))) ] [ text "Newer" ]
                 ]
                    ++ List.map viewPartitionDetail topicDetail.partitionDetails
                )

        Failure error ->
            div [] [ text "Something went wrong while fetching topic" ]

        Loading ->
            div [] [ text "Loading topic, please hold on..." ]


viewPartitionDetail : PartitionDetail -> Html Msg
viewPartitionDetail partitionDetail =
    div []
        [ table []
            ([ thead []
                [ td [] [ text "partition" ]
                , td [] [ text "offset" ]
                , td [] [ text "message" ]
                ]
             ]
                ++ List.map viewMessage partitionDetail.messages
            )
        ]


viewMessage : TopicMessage -> Html Msg
viewMessage message =
    tr []
        [ td [] [ text (String.fromInt message.partition) ]
        , td [] [ text (String.fromInt message.offset) ]
        , td [] [ text message.json ]
        ]


viewTopicListItem : Topic -> Html Msg
viewTopicListItem topic =
    let
        linkText =
            topic.name ++ " (" ++ String.fromInt topic.partitionCount ++ " partitions)"
    in
    div []
        [ Html.a [ class "nav-link", href (getPath (ViewTopicRoute topic.name Dict.empty)) ] [ text linkText ] ]


viewTopics : RemoteData Http.Error (List Topic) -> Html Msg
viewTopics topicsResponse =
    case topicsResponse of
        NotAsked ->
            div [] [ text "Should not be here!" ]

        Success topics ->
            div []
                (List.map viewTopicListItem topics)

        Failure error ->
            div [] [ text "Something went wrong while fetching topics" ]

        Loading ->
            div [] [ text "Loading topics, please hold on..." ]
