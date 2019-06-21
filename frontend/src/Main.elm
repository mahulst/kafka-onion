module Main exposing (Model, Msg(..), Page(..), init, main, update, view)

import Browser
import Browser.Navigation exposing (Key)
import Dict exposing (Dict)
import Element
import Element.Background
import Element.Font
import Http
import Json.Encode as E
import Pages.SendMessage as SendMessage exposing (Msg(..))
import Pages.TopicDetail as TopicDetail
import Pages.TopicOverview as TopicOverview exposing (Msg(..))
import RemoteData exposing (RemoteData(..))
import Routes exposing (Route, getTopicOverViewPath, parseUrl)
import Set
import Shared exposing (Flags, getLinkStyle)
import Topic exposing (PartitionDetail, PartitionOffsets, Topic, TopicDetail, decodeTopicDetail, decodeTopics)
import Url exposing (Url)



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


type alias Model =
    { page : Page
    , key : Key
    , flags : Flags
    , route : Route
    }


type Page
    = TopicOverviewPage TopicOverview.Model
    | TopicDetailPage TopicDetail.Model
    | SendMessagePage SendMessage.Model
    | PageNone


loadCurrentPage : ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
loadCurrentPage ( model, cmd ) =
    let
        ( page, newCmd ) =
            case model.route of
                Routes.NotFound ->
                    ( PageNone, Cmd.none )

                Routes.SendMessageRoute topicName partition ->
                    let
                        pageModel =
                            { topicDetailResponse = Loading, partition = partition, message = Nothing }
                    in
                    ( SendMessagePage pageModel, fetchTopicDetail model.flags.apiUrl topicName Dict.empty )

                Routes.RootRoute ->
                    ( TopicOverviewPage { topicsResponse = Loading }, fetchTopics model.flags.apiUrl )

                Routes.TopicsRoute ->
                    ( TopicOverviewPage { topicsResponse = Loading }, fetchTopics model.flags.apiUrl )

                Routes.ViewTopicRoute a offsets ->
                    ( TopicDetailPage { topicDetailResponse = Loading, messagesInJsonViewer = Set.empty }, fetchTopicDetail model.flags.apiUrl a offsets )
    in
    ( { model | page = page }, Cmd.batch [ cmd, newCmd ] )


init : Flags -> Url -> Key -> ( Model, Cmd Msg )
init flags url key =
    ( { page = PageNone, key = key, flags = flags, route = parseUrl url }, Cmd.none ) |> loadCurrentPage


encodePartitionOffsets : PartitionOffsets -> E.Value
encodePartitionOffsets partitionOffsets =
    E.dict String.fromInt E.int partitionOffsets


fetchTopics : String -> Cmd Msg
fetchTopics apiUrl =
    Http.get
        { url = apiUrl ++ "/api/topics"
        , expect = Http.expectJson (RemoteData.fromResult >> TopicsResponse) decodeTopics
        }
        |> Cmd.map TopicOverviewMsg


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


type Msg
    = OnUrlRequest Browser.UrlRequest
    | OnUrlChange Url
    | SendMessageMsg SendMessage.Msg
    | TopicOverviewMsg TopicOverview.Msg
    | TopicDetailMsg TopicDetail.Msg
    | TopicDetailResponse (RemoteData Http.Error TopicDetail)
    | Noop


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model.page ) of
        ( Noop, _ ) ->
            ( model, Cmd.none )

        ( OnUrlChange url, _ ) ->
            ( { model | route = parseUrl url }, Cmd.none ) |> loadCurrentPage

        ( OnUrlRequest urlRequest, _ ) ->
            case urlRequest of
                Browser.Internal url ->
                    ( model
                    , Browser.Navigation.pushUrl model.key (Url.toString url)
                    )

                Browser.External url ->
                    ( model
                    , Browser.Navigation.load url
                    )

        ( TopicDetailResponse topicDetailResponse, page ) ->
            case page of
                TopicDetailPage pageModel ->
                    let
                        newPageModel =
                            { pageModel | topicDetailResponse = topicDetailResponse }
                    in
                    ( { model | page = TopicDetailPage newPageModel }, Cmd.none )

                SendMessagePage pageModel ->
                    let
                        newPageModel =
                            { pageModel | topicDetailResponse = topicDetailResponse }
                    in
                    ( { model | page = SendMessagePage newPageModel }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ( TopicOverviewMsg subMsg, TopicOverviewPage pageModel ) ->
            let
                ( newPageModel, _ ) =
                    TopicOverview.update model.flags subMsg pageModel
            in
            ( { model | page = TopicOverviewPage newPageModel }, Cmd.none )

        ( SendMessageMsg subMsg, SendMessagePage pageModel ) ->
            let
                ( newPageModel, newSubCmd ) =
                    SendMessage.update model.flags subMsg pageModel
            in
            ( { model | page = SendMessagePage newPageModel }, newSubCmd |> Cmd.map SendMessageMsg )

        ( TopicDetailMsg subMsg, TopicDetailPage pageModel ) ->
            let
                ( newPageModel, newSubCmd ) =
                    TopicDetail.update model.flags subMsg pageModel
            in
            ( { model | page = TopicDetailPage newPageModel }, newSubCmd |> Cmd.map TopicDetailMsg )

        _ ->
            ( model, Cmd.none )



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
                { url = getTopicOverViewPath
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
                    TopicDetail.view pageModel |> Element.map TopicDetailMsg

                TopicOverviewPage pageModel ->
                    TopicOverview.view pageModel |> Element.map TopicOverviewMsg

                SendMessagePage sendMessagePageModel ->
                    SendMessage.view sendMessagePageModel |> Element.map SendMessageMsg

                PageNone ->
                    Element.el [] (Element.text "Sorry, can't find this page")
    in
    Element.column [ Element.width (Element.fill |> Element.maximum 1600), Element.centerX ]
        [ body ]
